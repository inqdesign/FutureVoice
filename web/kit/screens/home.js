/* nawana UI kit — one screen. Imports the shared base from ../core.js; registered by ../nawana-ui.js. */
import { NwScreen, STR, esc, icon } from "../core.js";

/* ═══════════════════════════ <nw-home> ═══════════════════════════
 * The Talk tab (ConversationHome.swift + NewsTopicSection.swift): the header (language pill,
 * Activity pill, avatar in its usage ring), the pixel greeting, the "Let's talk" ring around the
 * idle Futureself surface, the "Tell me more about you" row, and News / Everyday / Scenarios.
 *   home.tapRing(); home.scrollTo(380); home.tab(1); home.tapRow(0)
 *   home.lists = { news:[[icon,title,sub]…], everyday:[…], scenarios:[…] }   (sub may be "")
 * Attributes: greeting, autoplay.
 * Laid out in points from real/home.png and real/home-scenarios.png (iPhone 17, ko).
 *
 * The learner's own chip row (DiscoverSection at HEAD — LearningPurposeStore.chips: purposes in the
 * order picked, then News, then Scenarios). Unset = the row the captures show (News · Everyday ·
 * Scenarios, tools in the capture's order); set = HEAD's header (the chip's own tool, then sliders).
 *   home.chips = ["interview","news","scenarios"]        keys: exam study interview work life travel everyday news scenarios
 *   home.field = { interview: [titles…] | "writing" | null }   field topics (person.crop.square rows, no caption)
 *                                                       above the chip's starters; null = "Add the role…" row
 *   await home.writeTopics([titles…], "interview")      refresh spins, "Writing topics for your field…", rows land
 *   await home.refreshNews(rows)                        news rows [icon|null, title, category]: null icon → the app's
 *                                                       categoryIcon, caption capitalized like `.capitalized`
 *   await home.tapTool("sliders"|"refresh"|"plus"); home.tab("news") also takes a key
 *   rows may carry a 4th element `true` = talked through (green check before the chevron) */

/* SF Symbols, traced. Filled glyphs unless the symbol is an outline. */
const SF = {
  globe: `<svg viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9.6"/><ellipse cx="12" cy="12" rx="4.2" ry="9.6"/><path d="M12 2.4v19.2M2.4 12h19.2M4 7h16M4 17h16"/></g></svg>`,
  calendar: `<svg viewBox="0 0 20 18"><path fill-rule="evenodd" fill="currentColor" d="M3.6 0h12.8A3.6 3.6 0 0 1 20 3.6v10.8a3.6 3.6 0 0 1-3.6 3.6H3.6A3.6 3.6 0 0 1 0 14.4V3.6A3.6 3.6 0 0 1 3.6 0zM3.5 4.7h13a1.6 1.6 0 0 1 1.6 1.6v8.2a1.6 1.6 0 0 1-1.6 1.6h-13a1.6 1.6 0 0 1-1.6-1.6V6.3a1.6 1.6 0 0 1 1.6-1.6z"/><g fill="currentColor">${[[8.26,7.28],[11.48,7.28],[14.7,7.28],[5.16,10.47],[8.26,10.47],[11.48,10.47],[14.7,10.47],[5.16,13.53],[8.26,13.53],[11.48,13.53]].map(([x,y])=>`<rect x="${x-.75}" y="${y-.75}" width="1.5" height="1.5" rx=".35"/>`).join("")}</g></svg>`,
  personBadge: `<svg viewBox="0 0 24 21"><path fill="currentColor" d="M14.6 1A9.4 9.4 0 1 1 9.2 18.2l.9-1.3A7.8 7.8 0 1 0 6.9 8.9l-1.6-.2A9.4 9.4 0 0 1 14.6 1z"/><ellipse fill="currentColor" cx="14.6" cy="7.6" rx="2.6" ry="2.8"/><path fill="currentColor" d="M9.9 17.4c1.1-2.1 2.8-3.1 4.7-3.1 2.2 0 3.9 1 5.2 2.6a7.8 7.8 0 0 1-9.9.5z"/><circle fill="currentColor" cx="5.6" cy="14.6" r="4.7"/><path d="M5.6 12.1v5M3.1 14.6h5" stroke="#fff" stroke-width="1.4" stroke-linecap="round"/></svg>`,
  sliders: `<svg viewBox="0 0 20 17"><g fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M1 2.6h7.8M12.8 2.6H18M1 8.5h2.4M7.4 8.5H18M1 14.4h7.8M12.8 14.4H18"/><circle cx="10.8" cy="2.6" r="2"/><circle cx="5.4" cy="8.5" r="2"/><circle cx="10.8" cy="14.4" r="2"/></g></svg>`,
  refresh: `<svg viewBox="0 0 17 20"><g fill="none" stroke="currentColor" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round"><path d="M10.3 4.5H8.5a7 7 0 1 0 7 7"/><path d="M7.4 1l3.1 3.3-3.1 3.2"/></g></svg>`,
  plus: `<svg viewBox="0 0 18 18"><path d="M9 1.5v15M1.5 9h15" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></svg>`,
  chevron: `<svg viewBox="0 0 7 12"><path d="M1.2 1.2L5.8 6l-4.6 4.8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  cpu: `<svg viewBox="0 0 20 20"><g fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3.8" y="3.8" width="12.4" height="12.4" rx="2"/><rect x="7" y="7" width="6" height="6" rx=".8"/><path d="M7.4 1v2.8M10 1v2.8M12.6 1v2.8M7.4 16.2V19M10 16.2V19M12.6 16.2V19M1 7.4h2.8M1 10h2.8M1 12.6h2.8M16.2 7.4H19M16.2 10H19M16.2 12.6H19" stroke-linecap="round"/></g></svg>`,
  fork: `<svg viewBox="0 0 20 22"><g fill="currentColor"><path d="M5 1.2c.5 0 .8.3.8.8v5.1h.9V2c0-.5.4-.8.8-.8s.8.3.8.8v5.1h.9V2c0-.5.3-.8.8-.8s.8.3.8.8v6.2c0 1.6-1 2.8-2.4 3.2v8.4c0 .7-.5 1.2-1.2 1.2s-1.2-.5-1.2-1.2v-8.4C4.6 11 3.6 9.8 3.6 8.2V2c0-.5.3-.8.8-.8z"/><path d="M15.4 1.2c.5 0 .9.4.9.9v17.7c0 .7-.5 1.2-1.2 1.2s-1.2-.5-1.2-1.2v-6.6h-1c-.5 0-.8-.4-.8-.8 0-5.6 1.6-11.2 3.3-11.2z"/></g></svg>`,
  run: `<svg viewBox="0 0 20 22"><g fill="currentColor"><circle cx="12.6" cy="2.8" r="2.1"/><path d="M9.3 6.4c.7-.6 1.7-.8 2.6-.4l2.3 1c.5.2.8.6 1 1l1.1 2.5 2.3.6c.6.2 1 .8.8 1.4-.1.6-.7.9-1.3.8l-2.9-.7c-.4-.1-.7-.4-.9-.7l-.6-1.3-1.2 3.6 2.5 2.1c.3.3.5.7.5 1.1v4.2c0 .6-.5 1.1-1.1 1.1s-1.1-.5-1.1-1.1v-3.7l-2.9-2.4-1.5 3.6c-.2.4-.5.7-1 .7H3.6c-.6 0-1.1-.5-1.1-1.1s.5-1.1 1.1-1.1h3.4L9.5 9l-1.3.6-1.4 2.4c-.3.5-1 .7-1.5.4-.5-.3-.7-1-.4-1.5l1.6-2.8c.1-.2.3-.4.5-.5z"/></g></svg>`,
  atom: `<svg viewBox="0 0 22 22"><g fill="none" stroke="currentColor" stroke-width="1.5"><ellipse cx="11" cy="11" rx="9.6" ry="3.8"/><ellipse cx="11" cy="11" rx="9.6" ry="3.8" transform="rotate(60 11 11)"/><ellipse cx="11" cy="11" rx="9.6" ry="3.8" transform="rotate(-60 11 11)"/></g><circle fill="currentColor" cx="11" cy="11" r="1.7"/></svg>`,
  newspaper: `<svg viewBox="0 0 22 20"><path fill="currentColor" fill-rule="evenodd" d="M6.2 1h12.6C20 1 21 2 21 3.2v12.6c0 1.7-1.4 3.2-3.2 3.2H4.2C2.4 19 1 17.6 1 15.8V7.4c0-.7.6-1.3 1.3-1.3H4V3.2C4 2 5 1 6.2 1zM4 8.1H3v7.7c0 .6.4 1 1 1s1-.4 1-1zM8 4.5h4.5v4.5H8zm6.2.4h3.7v1.4h-3.7zm0 3h3.7v1.4h-3.7zM8 11h9.9v1.4H8zm0 3h9.9v1.4H8z"/></svg>`,
  wave: `<svg viewBox="0 0 22 22"><path fill="currentColor" d="M4.5 6.2c.6-.5 1.4-.4 1.9.2l4.7 5.6.6-.5-5.9-7c-.5-.6-.4-1.4.2-1.9s1.4-.4 1.9.2l5.9 7 .6-.5-4.9-5.9c-.5-.6-.4-1.4.2-1.9.6-.5 1.4-.4 1.9.2l4.9 5.9.6-.5-3.6-4.3c-.5-.6-.4-1.4.2-1.9.6-.5 1.4-.4 1.9.2l5.4 6.4c2.5 3 2.1 7.4-.9 9.9-2.6 2.2-6.2 2.3-8.9.6-.8-.5-1.5-1.1-2.1-1.8L4.3 8.1c-.5-.6-.4-1.4.2-1.9z"/></svg>`,
  cup: `<svg viewBox="0 0 24 20"><g fill="currentColor"><path d="M4.4 2.6C4.4 1.5 7.6.8 11.4.8s7 .7 7 1.8v.4c.4-.2.9-.3 1.4-.3 1.8 0 3 1.2 3 2.8 0 2.2-2.1 3.6-5.3 4.3-1.2 2-3.4 3.2-6.1 3.2-3.9 0-7-2.7-7-6.6zm14.1 2.3c0 1-.1 2-.4 2.9 2-.6 3-1.5 3-2.4 0-.6-.4-1.1-1.1-1.1-.6 0-1.1.2-1.5.6zM11.4 2.3c-2.9 0-5 .5-5 .9s2.1.9 5 .9 5-.4 5-.9-2.1-.9-5-.9z"/><path d="M.6 14.2c0-1.4 2.7-2.4 5.9-2.9 1.3 1.3 3 2 4.9 2s3.6-.7 4.9-2c3.2.5 5.9 1.5 5.9 2.9 0 2-4.8 3.6-10.8 3.6S.6 16.2.6 14.2z"/></g></svg>`,
  map: `<svg viewBox="0 0 22 22"><path fill="currentColor" d="M1 5.2c0-.5.3-.9.7-1.1L6.6 2v16.7l-4.4 1.9C1.6 20.9 1 20.4 1 19.8zm7 12.7V1.4l6 2.7v16.4zm7.4 2.6V3.9l4.4-1.9c.6-.3 1.2.2 1.2.8V17c0 .5-.3.9-.7 1.1z"/></svg>`,
  bag: `<svg viewBox="0 0 20 22"><path fill="currentColor" fill-rule="evenodd" d="M7 5V4.3C7 2.4 8.3 1 10 1s3 1.4 3 3.3V5h2.7C17.5 5 19 6.5 19 8.3v9.4c0 1.8-1.5 3.3-3.3 3.3H4.3C2.5 21 1 19.5 1 17.7V8.3C1 6.5 2.5 5 4.3 5zm1.6 0h2.8v-.7c0-.9-.6-1.6-1.4-1.6S8.6 3.4 8.6 4.3z"/></svg>`,
  cross: `<svg viewBox="0 0 24 20"><path fill="currentColor" fill-rule="evenodd" d="M8 4V3c0-1.1.9-2 2-2h4c1.1 0 2 .9 2 2v1h4.3C22 4 23 5 23 6.7v9.6c0 1.6-1.1 2.7-2.7 2.7H3.7C2 19 1 18 1 16.3V6.7C1 5 2 4 3.7 4zm1.6 0h4.8v-.8c0-.2-.2-.4-.4-.4H10c-.2 0-.4.2-.4.4zm1.2 5.1V7.6c0-.4.3-.7.7-.7h1c.4 0 .7.3.7.7v1.5h1.5c.4 0 .7.3.7.7v1c0 .4-.3.7-.7.7h-1.5v1.5c0 .4-.3.7-.7.7h-1c-.4 0-.7-.3-.7-.7v-1.5H9.3c-.4 0-.7-.3-.7-.7v-1c0-.4.3-.7.7-.7z"/></svg>`,
  bed: `<svg viewBox="0 0 24 18"><path fill="currentColor" d="M4.2 1h15.6C21 1 22 2 22 3.2v4.4c.6.4 1 1 1 1.8v6.4c0 .6-.5 1.2-1.2 1.2s-1.2-.5-1.2-1.2v-1.2H3.4v1.2c0 .6-.5 1.2-1.2 1.2S1 17.4 1 16.8V9.4c0-.8.4-1.4 1-1.8V3.2C2 2 3 1 4.2 1zm.8 3.8V7h5.6V4.8c0-.5-.4-.9-.9-.9H5.9c-.5 0-.9.4-.9.9zm8.4 0V7H19V4.8c0-.5-.4-.9-.9-.9h-3.8c-.5 0-.9.4-.9.9z"/></svg>`,
  tram: `<svg viewBox="0 0 18 24"><path fill="currentColor" fill-rule="evenodd" d="M5.3 1h7.4C15 1 16.8 2.8 16.8 5.1v10.8c0 1.8-1.2 3.3-2.8 3.8l1.4 2.3c.2.4.1.8-.3 1-.4.2-.8.1-1-.3l-1.2-2h-7.8l-1.2 2c-.2.4-.6.5-1 .3s-.5-.6-.3-1L4 19.7c-1.6-.5-2.8-2-2.8-3.8V5.1C1.2 2.8 3 1 5.3 1zm-.9 3.8c-.5 0-.9.4-.9.9v4.6c0 .5.4.9.9.9h9.2c.5 0 .9-.4.9-.9V5.7c0-.5-.4-.9-.9-.9zM6.9 2.4c-.4 0-.6.2-.6.6s.2.6.6.6h4.2c.4 0 .6-.2.6-.6s-.2-.6-.6-.6zM5 14a1.3 1.3 0 1 0 0 2.6A1.3 1.3 0 0 0 5 14zm8 0a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6z"/></svg>`,
  people: `<svg viewBox="0 0 26 18"><g fill="currentColor"><circle cx="7.6" cy="5.2" r="3.3"/><circle cx="17.6" cy="4.6" r="3.9"/><path d="M1 16.2c0-2.8 2.9-5.2 6.6-5.2 1.5 0 2.8.4 3.9 1-1.2 1.1-2 2.5-2.2 4.2H1.6c-.4 0-.6-.2-.6-.6z"/><path d="M10.6 16.4c0-3.4 3.1-5.7 7-5.7s7 2.3 7 5.7c0 .4-.3.6-.7.6H11.3c-.4 0-.7-.2-.7-.6z"/></g></svg>`,
  house: `<svg viewBox="0 0 24 22"><g fill="currentColor"><path d="M17.6 2.4h2.2v4.4l-2.2-1.9z"/><path fill-rule="evenodd" d="M12 4.6l7.6 6.6v8c0 1-.8 1.8-1.8 1.8H6.2c-1 0-1.8-.8-1.8-1.8v-8zm-1.6 9.6v6.8h3.2v-6.8z"/><path d="M11.2 1.3c.5-.4 1.1-.4 1.6 0l10 8.6c.4.3.4.9.1 1.2-.3.4-.9.4-1.2.1L12 2.9l-9.7 8.3c-.4.3-.9.3-1.2-.1-.3-.3-.3-.9.1-1.2z"/></g></svg>`,
  briefcase: `<svg viewBox="0 0 24 20"><path fill="currentColor" fill-rule="evenodd" d="M8 4V3c0-1.1.9-2 2-2h4c1.1 0 2 .9 2 2v1h4.3C22 4 23 5 23 6.7V10H1V6.7C1 5 2 4 3.7 4zm1.6 0h4.8v-.8c0-.2-.2-.4-.4-.4H10c-.2 0-.4.2-.4.4zM1 11.4h9.6v.9c0 .5.4.9.9.9h1c.5 0 .9-.4.9-.9v-.9H23v4.9c0 1.6-1.1 2.7-2.7 2.7H3.7C2 19 1 18 1 16.3z"/></svg>`,
  person: `<svg viewBox="0 0 20 22"><g fill="currentColor"><circle cx="10" cy="6" r="4.6"/><path d="M1.6 19.6c0-4 3.8-6.9 8.4-6.9s8.4 2.9 8.4 6.9c0 .8-.6 1.4-1.4 1.4H3c-.8 0-1.4-.6-1.4-1.4z"/></g></svg>`,
  stack: `<svg viewBox="0 0 22 22"><g fill="none" stroke="currentColor" stroke-width="1.6"><rect x="1.8" y="7.6" width="18.4" height="12.6" rx="2.6"/><path d="M4.4 4.8h13.2M6.6 2h8.8" stroke-linecap="round"/></g></svg>`,
  /* purpose chips (StarterSituation.interview icons, fieldIcon, the ask row) */
  personSq: `<svg viewBox="0 0 22 22"><defs><clipPath id="psq"><rect x="1" y="1" width="20" height="20" rx="4.6"/></clipPath></defs><rect x="1.8" y="1.8" width="18.4" height="18.4" rx="4" fill="none" stroke="currentColor" stroke-width="1.6"/><g fill="currentColor" clip-path="url(#psq)"><circle cx="11" cy="8.6" r="3.4"/><path d="M3.6 21c.6-4 3.6-6.6 7.4-6.6s6.8 2.6 7.4 6.6z"/></g></svg>`,
  qBubble: `<svg viewBox="0 0 22 22"><path d="M11 2.2c5 0 9 3.4 9 7.7s-4 7.7-9 7.7c-.9 0-1.8-.1-2.6-.3L4.2 19.8c-.4.2-.8-.2-.7-.6l.8-3.2C2.9 14.6 2 12.4 2 9.9 2 5.6 6 2.2 11 2.2z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M8.9 7.9c.1-1.2 1-2 2.2-2 1.3 0 2.2.8 2.2 1.9 0 .9-.5 1.4-1.3 1.9-.6.4-.9.7-.9 1.4v.3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><circle cx="11.1" cy="13.4" r="1" fill="currentColor"/></svg>`,
  chartBar: `<svg viewBox="0 0 22 20"><g fill="none" stroke="currentColor" stroke-width="1.6"><rect x="1.8" y="10.6" width="4.4" height="7.6" rx="1.2"/><rect x="8.8" y="6.2" width="4.4" height="12" rx="1.2"/><rect x="15.8" y="1.8" width="4.4" height="16.4" rx="1.2"/></g></svg>`,
  briefO: `<svg viewBox="0 0 24 20"><g fill="none" stroke="currentColor" stroke-width="1.6"><rect x="1.8" y="4.8" width="20.4" height="13.4" rx="2.8"/><path d="M8.4 4.8V3.2c0-.8.6-1.4 1.4-1.4h4.4c.8 0 1.4.6 1.4 1.4v1.6M1.8 10.6h20.4"/></g></svg>`,
  banknote: `<svg viewBox="0 0 26 18"><g fill="none" stroke="currentColor" stroke-width="1.6"><rect x="1.8" y="1.8" width="22.4" height="14.4" rx="2.6"/><circle cx="13" cy="9" r="3.2"/></g><g fill="currentColor"><circle cx="5.6" cy="9" r="1.1"/><circle cx="20.4" cy="9" r="1.1"/></g></svg>`,
  pencilSq: `<svg viewBox="0 0 22 22"><path d="M10.6 3.4H5.2C3.4 3.4 2 4.8 2 6.6v10.2C2 18.6 3.4 20 5.2 20h10.2c1.8 0 3.2-1.4 3.2-3.2v-5.4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><path d="M17.6 1.9c.6-.6 1.6-.6 2.2 0l.3.3c.6.6.6 1.6 0 2.2l-8.4 8.4-3.2 1 1-3.2z" fill="currentColor"/></svg>`,
  checkFill: `<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="9.4" fill="currentColor"/><path d="M5.9 10.3l2.8 2.8 5.4-6.1" fill="none" stroke="#fff" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  /* NewsTopicSection.categoryIcon's other answers */
  music: `<svg viewBox="0 0 18 22"><path fill="currentColor" d="M15.6 1.2c.6-.1 1.1.3 1.1.9v13.4c0 2-1.7 3.6-3.9 3.6-1.8 0-3-1-3-2.4 0-1.7 1.6-2.8 3.5-3.1l1.6-.3V6.2L7.2 7.7v10c0 2-1.7 3.6-3.9 3.6-1.8 0-3-1-3-2.4 0-1.7 1.6-2.8 3.5-3.1l1.6-.3V4c0-.5.3-.9.8-1z"/></svg>`,
  airplane: `<svg viewBox="0 0 22 22"><path fill="currentColor" d="M19.6 2.4c.9.9.6 2.4-.5 3.5l-3.6 3.5 2.2 9.6c.1.4 0 .8-.3 1.1l-.8.8c-.4.4-1 .3-1.3-.2l-4.3-8.1-3.5 3.4.4 2.9c0 .3-.1.6-.3.8l-.6.6c-.3.3-.9.3-1.1-.1l-1.9-3.3-3.3-1.9c-.4-.2-.4-.8-.1-1.1l.6-.6c.2-.2.5-.3.8-.3l2.9.4 3.4-3.5-8.1-4.3c-.5-.3-.6-.9-.2-1.3l.8-.8c.3-.3.7-.4 1.1-.3l9.6 2.2 3.5-3.6c1.1-1.1 2.6-1.4 3.5-.5z"/></svg>`,
  chartUp: `<svg viewBox="0 0 22 20"><g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M1.8 1.8v16.4h18.4"/><path d="M5.4 13.4l4.4-4.6 3.4 3.2 5.6-6.2"/><path d="M15.2 5.6h3.8v3.8"/></g></svg>`,
  film: `<svg viewBox="0 0 22 20"><path fill="currentColor" fill-rule="evenodd" d="M4.4 1h13.2C19.5 1 21 2.5 21 4.4v11.2c0 1.9-1.5 3.4-3.4 3.4H4.4C2.5 19 1 17.5 1 15.6V4.4C1 2.5 2.5 1 4.4 1zM3 4.4v1.8h2V3h-.6C3.6 3 3 3.6 3 4.4zm0 4.7v1.8h2V9.1zm0 4.7v1.8c0 .8.6 1.4 1.4 1.4H5v-3.2zM17 3v3.2h2V4.4c0-.8-.6-1.4-1.4-1.4zm0 6.1v1.8h2V9.1zm0 4.7V17h.6c.8 0 1.4-.6 1.4-1.4v-1.8zM7 3v14h8V3z"/></svg>`,
  game: `<svg viewBox="0 0 26 18"><path fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" d="M7.4 2.2h11.2c3 0 5.2 2.4 5.6 5.6l.6 5.4c.2 1.6-1 2.8-2.4 2.8-1 0-1.8-.5-2.4-1.4l-1.2-1.8H7.2L6 14.6c-.6.9-1.4 1.4-2.4 1.4-1.4 0-2.6-1.2-2.4-2.8l.6-5.4C2.2 4.6 4.4 2.2 7.4 2.2z"/><path d="M7.4 6v4.4M5.2 8.2h4.4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><g fill="currentColor"><circle cx="17.6" cy="6.8" r="1.1"/><circle cx="19.8" cy="9.4" r="1.1"/></g></svg>`,
  phone: `<svg viewBox="0 0 20 20"><path fill="currentColor" d="M5.3 1.3c.5-.2 1.1 0 1.4.5l1.9 3.4c.3.5.2 1.1-.2 1.5L7 8.1c.9 2 2.6 3.8 4.7 4.8l1.4-1.4c.4-.4 1-.5 1.5-.2l3.4 1.9c.5.3.7.9.5 1.4l-.8 2.3c-.4 1.1-1.5 1.8-2.7 1.6C8.6 17.7 2.4 11.5 1.6 5.1 1.4 3.9 2.1 2.8 3.2 2.4z"/></svg>`,
  book: `<svg viewBox="0 0 22 20"><path fill="currentColor" d="M1 3.2C1 2.4 1.6 1.8 2.4 1.8c3 0 5.6.6 7.8 2v14.4c-2.2-1.2-4.8-1.8-7.8-1.8-.8 0-1.4-.6-1.4-1.4zm20 0v11.8c0 .8-.6 1.4-1.4 1.4-3 0-5.6.6-7.8 1.8V3.8c2.2-1.4 4.8-2 7.8-2 .8 0 1.4.6 1.4 1.4z"/></svg>`,
  heart: `<svg viewBox="0 0 22 20"><path fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" d="M11 18.6S1.8 13.2 1.8 6.8C1.8 3.9 3.9 1.8 6.6 1.8c1.9 0 3.5 1 4.4 2.6.9-1.6 2.5-2.6 4.4-2.6 2.7 0 4.8 2.1 4.8 5 0 6.4-9.2 11.8-9.2 11.8z"/></svg>`,
};
/* iOS ProgressView: eight spokes, the leading one darkest, turning in steps */
const SPIN = s => `<span class="spin" style="width:${s}px;height:${s}px">${[...Array(8)].map((_, i) => `<i style="transform:rotate(${i * 45}deg);opacity:${(.25 + .75 * (8 - i) / 8).toFixed(2)}"></i>`).join("")}</span>`;
/* glyph boxes in points: [width, height] as measured in the capture */
const GLYPH = {
  cpu: [15, 15], fork: [16.1, 18.6], run: [15.5, 18], atom: [17.5, 17.5], newspaper: [18.5, 16.8], wave: [18, 18], cup: [20.6, 16.7], map: [16.8, 16.1],
  bag: [14.2, 16.1], cross: [18.3, 17.2], bed: [20.3, 13.7], tram: [14, 19.7], people: [22, 14.7], house: [19, 16.8], briefcase: [19, 16.5], person: [15.5, 17.2], stack: [17.5, 17.5], plus: [13, 13],
  phone: [15.6, 15.6], book: [18.3, 16.6], personSq: [16.5, 16.5], qBubble: [17.5, 17.5], chartBar: [17.6, 16], briefO: [19, 16], banknote: [21, 14.6], pencilSq: [17.5, 17.5],
  music: [13.6, 16.8], airplane: [17.5, 17.5], chartUp: [17.6, 16], film: [18.3, 16.6], game: [21, 14.6], heart: [17.6, 16],
};
/* NewsTopicSection.categoryIcon: a free-form interest category → its glyph (newspaper.fill fallback) */
const categoryIcon = c => {
  c = (c || "").toLowerCase(); if (!c) return "newspaper";
  if (c.includes("ai") || c.includes("tech")) return "cpu";
  if (c.includes("cook") || c.includes("food")) return "fork";
  if (c.includes("sport") || c.includes("fitness")) return "run";
  if (c.includes("music")) return "music";
  if (c.includes("travel")) return "airplane";
  if (c.includes("science")) return "atom";
  if (c.includes("business") || c.includes("finance")) return "chartUp";
  if (c.includes("film") || c.includes("movie") || c.includes("tv")) return "film";
  if (c.includes("game")) return "game";
  if (c.includes("health")) return "heart";
  return "newspaper";
};
/* Swift's String.capitalized: every word's first letter up, the rest down ("ai / tech" → "Ai / Tech") */
const capitalized = s => String(s || "").toLowerCase().replace(/(^|[\s/\-–(])(\p{L})/gu, (m, a, b) => a + b.toUpperCase());
/* DiscoverChip.label (chrome) */
const CHIP = {
  ko: { exam: "시험", study: "전공", interview: "면접", work: "일", life: "생활", travel: "여행", everyday: "일상", news: "뉴스", scenarios: "상황" },
  en: { exam: "Exam", study: "Studies", interview: "Interview", work: "Work", life: "Life", travel: "Travel", everyday: "Everyday", news: "News", scenarios: "Scenarios" },
};
const FIELD_CHIPS = ["study", "work", "interview"];
const g = (n, w, h) => SF[n] ? SF[n].replace("<svg ", `<svg width="${w}" height="${h}" `) : icon(n);
/* names the page may pass in `lists` from the first kit version → today's SF traces */
const ALIAS = { chip: "cpu", leaf: "fork", ball: "run", hosp: "cross", brief: "briefcase", home: "house", user: "person" };

/* page geometry (points, scroll offset 0) — from the capture */
const LIST_TOP = 757.5, CONTENT_BOTTOM_MARGIN = 874 - 58;  // bottom: 24 content margin + 34 home indicator

class NwHome extends NwScreen {
  static poses = ["home", "everyday-bottom", "news-scrolled", "scenarios", "purpose", "purpose-ask", "purpose-writing", "purpose-news", "purpose-scenarios"];
  constructor() {
    super(`
      :host{background:#F2F2F7;--blue:#0A5CF5}
      .sc{position:absolute;left:0;right:0;top:0;height:874px;transition:transform .9s cubic-bezier(.45,0,.2,1)}
      /* header — fixed, iOS 26 glass */
      .hdr{position:absolute;left:0;right:0;top:62px;height:44px;z-index:6}
      .gl{position:absolute;top:0;height:44px;border-radius:22px;background:#FBFBFE;
        box-shadow:inset 0 0 0 1px rgba(255,255,255,.95),0 0 0 .5px rgba(0,0,0,.035),0 4px 16px rgba(0,0,0,.065);display:flex;align-items:center;justify-content:center}
      .lang{left:16px;width:59px;gap:6px;color:var(--blue)}
      .lang svg{width:14.7px;height:14.7px}
      .lang b{font-size:13.7px;font-weight:600;letter-spacing:-.1px;line-height:1}
      .act{left:159.5px;width:83px;gap:6.5px;padding-left:1px}
      .act svg{width:19.4px;height:17.5px;color:#6E6E73}
      .act b{font-size:15px;font-weight:600;letter-spacing:-.2px}
      .me{left:337.5px;width:44px;border-radius:50%}
      .me .trk{position:absolute;left:3px;top:3px;width:38px;height:38px;border-radius:50%;box-shadow:inset 0 0 0 3px rgba(118,118,128,.12)}
      .me .av{position:absolute;left:8px;top:8px;width:28px;height:28px;border-radius:50%;background:rgba(120,120,128,.16);display:grid;place-items:center;
        font:600 11.8px/1 ui-rounded,"SF Pro Rounded",var(--sans);color:rgba(60,60,67,.6)}
      /* iOS 26 soft scroll-edge under the header */
      .edge{position:absolute;left:0;right:0;top:0;height:136px;z-index:5;pointer-events:none;
        backdrop-filter:blur(7px);-webkit-backdrop-filter:blur(7px);
        -webkit-mask-image:linear-gradient(#000 0,#000 45%,transparent 100%);mask-image:linear-gradient(#000 0,#000 45%,transparent 100%);
        background:linear-gradient(rgba(244,244,248,.9),rgba(244,244,248,.78) 50%,rgba(244,244,248,0))}
      /* hero */
      .greet{position:absolute;left:24px;right:24px;top:174.2px;text-align:center;font-family:"Geist Pixel","Galmuri14",monospace;font-size:28px;line-height:36.67px;letter-spacing:0}
      .ring{position:absolute;left:51px;top:287px;width:300px;height:300px;border-radius:50%;transition:transform .25s,opacity .25s}
      .ring .trk{position:absolute;inset:0;border-radius:50%;box-shadow:inset 0 0 0 20px rgba(0,0,0,.015)}
      .ring .srf{position:absolute;left:20px;top:20px;width:260px;height:260px;border-radius:50%;overflow:hidden}
      .ring nw-futureself{position:absolute;inset:0;width:100%;height:100%;display:block}
      .ring .sep{position:absolute;inset:0;border-radius:50%;box-shadow:inset 0 0 0 .5px rgba(60,60,67,.12);pointer-events:none}
      .ring .lab{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;padding-top:1px}
      .ring .lab b{font-family:"Geist Pixel","Galmuri14",monospace;font-weight:400;font-size:20px;line-height:24px;letter-spacing:0}
      .ring .lab small{font-size:13px;line-height:16px;font-weight:500;color:rgba(60,60,67,.6);font-variant-numeric:tabular-nums;letter-spacing:-.1px}
      .ring.tap{transform:scale(.96)}
      /* cards */
      .about{position:absolute;left:20px;right:20px;top:621px;height:66.3px;border-radius:20px;background:#fff;display:flex;align-items:center;gap:12px;padding:0 16px 0 13.7px;transition:background .2s}
      .about .bi{width:23.7px;height:20px;color:var(--blue);flex:0 0 auto}
      .about .ch{margin-left:20px}
      .about .tx{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px;padding-left:2px}
      .about .tx b{font-size:15px;line-height:18px;font-weight:600;letter-spacing:-.2px}
      .about .tx small{font-size:12px;line-height:15px;color:rgba(60,60,67,.6);letter-spacing:-.07px}
      .ch{flex:0 0 auto;width:6.7px;height:11.4px;color:rgba(60,60,67,.3);display:block}
      .tabs{position:absolute;left:19.67px;right:20px;top:711.7px;height:33.3px;display:flex;gap:8px;align-items:center}
      .tabs span{height:33.3px;padding:0 14.3px;border-radius:17px;background:#fff;display:flex;align-items:center;font-size:15px;font-weight:500;letter-spacing:-.2px;transition:background .15s ease-out,color .15s ease-out}
      .tabs span.on{background:#000;color:#fff}
      .tabs .tools{margin-left:auto;display:flex;align-items:center;gap:11.7px;color:var(--blue);background:none!important;padding:0;height:auto}
      .tabs .tools .sl{width:16.7px;height:14.3px;margin-right:0} .tabs .tools .rf{width:14.7px;height:18px;margin-right:.7px}
      .tabs .tools .pl{width:15px;height:15px;margin-right:2px}
      .list{position:absolute;left:20px;right:20px;top:${LIST_TOP}px;display:flex;flex-direction:column;gap:10px;transition:opacity .2s}
      .list.swap{opacity:0}
      .row{background:#fff;border-radius:18px;display:flex;align-items:center;gap:12px;padding:14px 14px 14px 14px;min-height:64px;transition:background .2s}
      .row .ic{flex:0 0 auto;width:36px;height:36px;border-radius:50%;background:rgba(10,92,245,.15);color:var(--blue);display:grid;place-items:center}
      .row .tx{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
      .row .tx b{font-size:15px;line-height:20px;margin:-1px 0;font-weight:500;letter-spacing:-.2px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
      .row .tx small{font-size:12px;line-height:14.3px;color:rgba(60,60,67,.6);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;letter-spacing:0}
      .row .ch{margin-left:20px}  /* HStack(spacing:12): text · 12 · Spacer(min 8) · 12 · chevron */
      .row .ok{flex:0 0 auto;width:20px;height:20px;color:#34C759;margin-left:20px;margin-right:-8px}
      .row .ok+.ch{margin-left:12px}
      .row.tap,.about.tap{background:#E5E5EA}
      /* HEAD's chip row: chips (scrolling + faded past three), then the chip's own tool · 20 · sliders */
      .tabs.head{left:20px}
      .tabs .cw{display:flex;gap:8px;min-width:0}
      .tabs .cw.many{flex:1;overflow:hidden;-webkit-mask-image:linear-gradient(90deg,#000 calc(100% - 20px),transparent);mask-image:linear-gradient(90deg,#000 calc(100% - 20px),transparent)}
      .tabs .cw span{flex:0 0 auto}
      .tabs.head .tools{gap:20px}
      .tabs .tools>*{transition:transform .15s,opacity .15s}
      .tabs .tools .pr{transform:scale(.82);opacity:.45}
      .tabs .tools .spin{margin:0 -1px;padding:0;border-radius:0;background:none}
      .spin{position:relative;display:inline-block;flex:0 0 auto;animation:sp .8s steps(8) infinite}
      .spin i{position:absolute;left:45.5%;top:0;width:9%;height:28%;border-radius:9px;background:#8E8E93;transform-origin:50% 178.5%}
      @keyframes sp{to{transform:rotate(360deg)}}
      .wait{display:flex;align-items:center;gap:10px;padding:0 0 0 0;height:22px;font-size:17px;line-height:22px;color:rgba(60,60,67,.6);letter-spacing:-.4px}
      .stack{display:flex;flex-direction:column;gap:10px}
    `, `
      <div class="sc">
        <div class="greet"></div>
        <div class="ring"><div class="trk"></div><div class="srf"><nw-futureself mode="idle" level="0" shape="circle" ring cell="12.8"></nw-futureself><div class="sep"></div><div class="lab"><b></b><small></small></div></div></div>
        <div class="about">${SF.personBadge.replace("<svg ", '<svg class="bi" ')}<span class="tx"><b class="a1"></b><small class="a2"></small></span>${SF.chevron.replace("<svg ", '<svg class="ch" ')}</div>
        <div class="tabs"></div>
        <div class="list"></div>
      </div>
      <div class="edge"></div>
      <div class="hdr">
        <div class="gl lang">${SF.globe}<b>EN</b></div>
        <div class="gl act">${SF.calendar}<b></b></div>
        <div class="gl me"><span class="trk"></span><span class="av"></span></div>
      </div>`);
    this.lists = null;
    this._chips = null; this._field = {}; this._busy = new Set();
    this._y = 0; this._tab = 0;
  }
  /** The chip row as keys; null = the captures' row (News · Everyday · Scenarios). */
  get chips() { return this._chips; }
  set chips(v) { this._chips = v && v.length ? [...v] : null; if (this._built) { this._renderTabs(); this._setTab(0); } }
  /** Field topics per field chip: [titles] | "writing" | null (nothing written yet → the ask row). */
  get field() { return this._field; }
  set field(v) { this._field = { ...(v || {}) }; if (this._built) this._setTab(this._tab); }
  get _head() { return !!this._chips; }
  _keys() { return this._chips || ["news", "everyday", "scenarios"]; }
  _key(i) { return typeof i === "string" ? i : this._keys()[i]; }
  _idx(i) { const k = this._keys().indexOf(this._key(i)); return k < 0 ? 0 : k; }
  _lists() {
    const ko = this.t === STR.ko, w = r => ko ? `상대: ${r}` : `with ${r}`;
    /* News: the capture's own pool (DebugCaptureHarness.seedNews); caption = category, capitalized. */
    const news = [
      ["cpu", "Did you see the new phone that folds three ways?", "Ai / Tech"],
      ["fork", "Have you heard beef tallow is making a comeback?", "Cooking"],
      ["cpu", "Did you see the home robot folding laundry?", "Ai / Tech"],
    ];
    /* Everyday: StarterSituation.all, in order (chrome — the app language). */
    const everyday = ko ? [
      ["wave", "처음 만난 사람과", ""], ["cup", "카페에서", w("바리스타")], ["fork", "식당에서", w("종업원")], ["map", "길에서", w("지나가는 사람")],
      ["bag", "옷 가게에서", w("점원")], ["cross", "병원에 전화하기", w("병원 접수 직원")], ["bed", "호텔에서", w("프런트 직원")],
      ["tram", "기차역에서", w("매표소 직원")], ["people", "친구와", ""], ["house", "이웃과", ""],
    ] : [
      ["wave", "Meeting someone new", ""], ["cup", "At a café", w("a barista")], ["fork", "At a restaurant", w("a server")], ["map", "On the street", w("a passerby")],
      ["bag", "At a clothing store", w("a shop assistant")], ["cross", "Calling a clinic", w("a clinic receptionist")], ["bed", "At a hotel", w("a front desk clerk")],
      ["tram", "At the train station", w("a ticket agent")], ["people", "With a friend", ""], ["house", "With a neighbor", ""],
    ];
    /* Scenarios: the learner's own, newest first (DebugCaptureHarness.seedScenarios — card title, role and
       categoryIcon are the composer's; material, so English), then the "All scenarios" tail. */
    const scenarios = [
      ["briefcase", "Job interview · panel round", w("Interviewer")],
      ["cup", "Café · catching up", w("Sarah (close friend)")],
      ["cross", "Doctor's visit", w("Doctor")],
      ["cross", "Pharmacy · picking up a prescription", w("Pharmacist")],
      ["stack", ko ? "모든 상황" : "All scenarios", "4"],
    ];
    /* StarterSituation.interview / .work: the ready-made rows under a field chip's own topics */
    const interview = [
      ["personSq", ko ? "자기소개 해 주세요" : "Tell me about yourself", w(ko ? "면접관" : "an interviewer")],
      ["qBubble", ko ? "지원 동기" : "Why do you want this job?", w(ko ? "면접관" : "an interviewer")],
      ["chartBar", ko ? "강점과 약점" : "Strengths and weaknesses", w(ko ? "면접관" : "an interviewer")],
      ["briefO", ko ? "자랑하고 싶은 프로젝트" : "A project you're proud of", w(ko ? "면접관" : "an interviewer")],
      ["banknote", ko ? "연봉 이야기" : "Talking about salary", w(ko ? "채용 담당자" : "a recruiter")],
    ];
    const work = [
      ["people", ko ? "회의에서 의견 말하기" : "Giving your view in a meeting", ""],
      ["chartUp", ko ? "진행 상황 보고" : "Your project update", w(ko ? "팀장님" : "your manager")],
      ["phone", ko ? "고객과 통화" : "A call with a client", w(ko ? "고객" : "a client")],
      ["cup", ko ? "동료와 가벼운 이야기" : "Small talk with a coworker", ""],
    ];
    return Object.assign({ news, everyday, scenarios, interview, work, study: [] }, this.lists || {});
  }
  build() {
    const t = this.t, ko = t === STR.ko;
    this.$(".greet").innerHTML = esc(this.getAttribute("greeting") || "What's on your mind this evening?").replace(/ (this|today|tonight)/, "<br>$1");
    this.$(".act b").textContent = t.activity;
    this.$(".av").textContent = this.getAttribute("initial") || (ko ? "하" : "H");
    this.$(".ring b").textContent = t.talk; this.$(".ring small").textContent = ko ? t.goal : "Today's goal 10 min";   // "Today's goal %lld min"
    this.$(".a1").textContent = t.aboutMe; this.$(".a2").textContent = t.aboutMeSub;
    this._renderTabs();
    this.reset();
  }
  _renderTabs() {
    const L = this.t === STR.ko ? CHIP.ko : CHIP.en, keys = this._keys(), tb = this.$(".tabs");
    const chips = keys.map(k => `<span class="chip" data-k="${k}">${esc(L[k] || k)}</span>`).join("");
    tb.classList.toggle("head", this._head);
    tb.innerHTML = this._head ? `<div class="cw${keys.length > 3 ? " many" : ""}">${chips}</div><span class="tools"></span>` : `${chips}<span class="tools"></span>`;
  }
  reset() { this._busy.clear(); this._setTab(0); this.scrollTo(0); }
  _row([ic, ti, su, done]) {
    const n = ALIAS[ic] || ic, [w, h] = GLYPH[n] || [16, 16];
    return `<div class="row"><span class="ic">${g(n, w, h)}</span><span class="tx"><b>${esc(ti)}</b>${su ? `<small>${esc(su)}</small>` : ""}</span>${done ? SF.checkFill.replace("<svg ", '<svg class="ok" ') : ""}${SF.chevron.replace("<svg ", '<svg class="ch" ')}</div>`;
  }
  _wait(text) { return `<div class="wait">${SPIN(20)}<span>${esc(text)}</span></div>`; }
  _fill(i) {
    const key = this._key(i), L = this._lists(), ko = this.t === STR.ko;
    let rows = (L[key] || []).map(r => key === "news" && !r[0] ? ["", r[1], capitalized(r[2]), r[3]] : r)
      .map(r => key === "news" && !r[0] ? [categoryIcon(r[2]), ...r.slice(1)] : r);
    let html = rows.map(r => this._row(r)).join("");
    if (FIELD_CHIPS.includes(key) && this._head) {
      // DiscoverSection.fieldContent: the role's topics (or what writing it buys), then the starters
      const f = this._field[key], fi = { study: "book", work: "briefcase", interview: "personSq" }[key];
      const ask = { study: ko ? "학교와 전공을 적으면 내 분야 주제를 만들어 줘요" : "Add your school and subject for topics from your field",
        work: ko ? "하는 일과 역할을 적으면 내 일에 맞춘 주제를 만들어 줘요" : "Add your job and role for topics from your work",
        interview: ko ? "지원하는 직무를 적으면 그 직무 면접 질문을 만들어 줘요" : "Add the role you're applying for — I'll ask its questions" }[key];
      const top = Array.isArray(f) ? f.slice(0, 8).map(ti => this._row([fi, ti, ""])).join("")
        : f === "writing" ? this._wait(ko ? "내 분야 주제를 만드는 중…" : "Writing topics for your field…")
        : this._row(["pencilSq", ask, ""]);
      html = top + html;
    }
    this.$(".list").innerHTML = html;
    this._tools(key);
  }
  /* header accessories follow the tab */
  _tools(key) {
    const sl = SF.sliders.replace("<svg ", '<svg class="sl" data-t="sliders" '), rf = SF.refresh.replace("<svg ", '<svg class="rf" data-t="refresh" ');
    const pl = SF.plus.replace("<svg ", '<svg class="pl" data-t="plus" '), spin = SPIN(17).replace('class="spin"', 'class="spin" data-t="refresh"');
    let html;
    if (!this._head) {
      // the captures' build: News → interests + refresh, Scenarios → build, Everyday → none
      html = key === "news" ? sl + rf : key === "scenarios" ? pl : "";
    } else {
      // HEAD: field chip with a role → "Other topics"; News with stories → refresh; Scenarios → +; sliders always last
      const f = this._field[key], lead = FIELD_CHIPS.includes(key) ? (f === "writing" ? spin : Array.isArray(f) ? rf : "")
        : key === "news" ? (this._busy.has("news") ? spin : (this._lists().news || []).length ? rf : "")
        : key === "exam" ? rf : key === "scenarios" ? pl : "";
      html = lead + sl;
    }
    this.$(".tools").innerHTML = html;
  }
  _setTab(i) { const k = this._key(i); this._tab = this._idx(i); this.$$(".tabs .chip").forEach(s => s.classList.toggle("on", s.dataset.k === k)); this._fill(k); }
  /** The page can't scroll past its own end — the list's last card stops above the home indicator. */
  _maxScroll() {
    const l = this.$(".list"); const h = l.scrollHeight || l.offsetHeight;
    return Math.max(0, LIST_TOP + h - CONTENT_BOTTOM_MARGIN);
  }
  scrollTo(y) {
    y = Math.max(0, Math.min(y, this._maxScroll())); this._y = y;
    this.$(".sc").style.transform = y ? `translateY(${-y}px)` : "none";
    // TalkHeroSection: the ring shrinks with the scroll (floor .3) and fades out between 110 and 250 pt.
    const r = this.$(".ring"), s = Math.max(.3, 1 - y / 450), o = y > 110 ? Math.max(0, 1 - (y - 110) / 140) : 1;
    r.style.transform = s < 1 ? `scale(${s})` : ""; r.style.opacity = o;
    return y;
  }
  async tab(i) {
    const l = this.$(".list"); l.classList.add("swap"); await this.sleep(160); this._setTab(i);
    if (this._y > this._maxScroll()) this.scrollTo(this._maxScroll());   // a shorter list pulls the page back
    await this.sleep(30); l.classList.remove("swap");
  }
  async tapRing() { const r = this.$(".ring"); const was = r.style.transform; r.style.transform = "scale(.96)"; await this.sleep(260); r.style.transform = was; }
  async tapRow(i) { const r = this.$$(".list .row")[i]; if (!r) return; r.classList.add("tap"); await this.sleep(260); r.classList.remove("tap"); }
  /** Press one of the row's header buttons (sliders · refresh · plus). */
  async tapTool(name) { const b = this.$(`.tools [data-t="${name}"]`); if (!b) return; b.classList.add("pr"); await this.sleep(180); b.classList.remove("pr"); await this.sleep(80); }
  /** A field chip's topics being written, then landing (PurposeTopicEngine: eight at a time). */
  async writeTopics(titles, chip = "interview", ms = 1800) {
    this._field[chip] = "writing"; if (this._key(this._tab) === chip) this._setTab(chip);
    await this.sleep(ms);
    const l = this.$(".list"); l.classList.add("swap"); await this.sleep(160);
    this._field[chip] = [...titles]; if (this._key(this._tab) === chip) this._setTab(chip);
    await this.sleep(30); l.classList.remove("swap");
  }
  /** The News chip's refresh: the button turns into a spinner, the stories swap. */
  async refreshNews(rows, ms = 1200) {
    if (this._key(this._tab) === "news") await this.tapTool("refresh");
    this._busy.add("news"); if (this._key(this._tab) === "news") this._tools("news");
    await this.sleep(ms);
    this._busy.delete("news");
    const l = this.$(".list"); l.classList.add("swap"); await this.sleep(160);
    this.lists = { ...(this.lists || {}), news: rows }; if (this._key(this._tab) === "news") this._setTab("news");
    await this.sleep(30); l.classList.remove("swap");
  }
  async pose(name) {
    this.stop();
    if (/^purpose/.test(name)) {
      // the learner's own row (no capture yet — HEAD's DiscoverSection); topics are placeholders until real output is taken
      this.chips = ["interview", "news", "scenarios"];
      this._field = name === "purpose-ask" ? {} : { interview: name === "purpose-writing" ? "writing" : ["(topic 1)", "(topic 2)", "(topic 3)", "(topic 4)", "(topic 5)", "(topic 6)", "(topic 7)", "(topic 8)"] };
      this._setTab(name === "purpose-news" ? "news" : name === "purpose-scenarios" ? "scenarios" : "interview"); this.scrollTo(380);
    }
    else if (name === "everyday-bottom") { this._setTab(1); this.scrollTo(1e4); }
    else if (name === "news-scrolled") { this._setTab(0); this.scrollTo(380); }
    else if (name === "scenarios") { this._setTab(2); this.scrollTo(1e4); }
    else { this._setTab(0); this.scrollTo(0); }
  }
  async demo() {
    await this.sleep(1200); this.beat(1); await this.tapRing(); await this.sleep(1100);
    this.scrollTo(380); await this.sleep(1400);
    for (let i = 0; i < 3; i++) { this.beat(2 + i); if (i) await this.tab(i); await this.sleep(1600); await this.tapRow(0); await this.sleep(500); }
    await this.sleep(1000);
  }
}

export { NwHome };
