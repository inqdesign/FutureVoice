// The one mail an applicant gets: "we have your application", from the founder.
// A creator's says he reads it and writes back; a challenger's says the payment
// is what finishes it and carries the way back to the checkout. Both carry the
// schedule, marked as planned (founder, 2026-11-12).
//
// Sent once, when an application is new. The words were approved by the founder
// on 2026-11-11 and promise only what the page already says: he reads every
// one himself, he writes back, cohort 1 starts 2026-12-01. Nothing here says
// whether anyone was picked.
//
// Korean or English, by the page the form came from (page_lang, 2026-11-12):
// /creators writes in Korean, /en/creators in English. The Korean words are
// unchanged by that; the English ones are written for the English page, never
// translated from these.
//
// It needs RESEND_API_KEY in the function's env. Without it nothing is sent
// and the application is still saved: a mail is never a reason to lose one.

const SITE = "https://nawana.app"
type Lang = "ko" | "en"
const FROM: Record<Lang, string> = {
  ko: "이응규 · nawana <hello@nawana.app>",
  en: "Eunggyu Lee · nawana <hello@nawana.app>",
}
const REPLY_TO = "hello@nawana.app"
const APP_STORE = "https://apps.apple.com/app/id6792794655"
const PLAY_STORE = "https://play.google.com/store/apps/details?id=com.roro.futurevoice"
const THREADS = ["@adaywithboram", "https://www.threads.com/@adaywithboram"]
const INSTAGRAM = ["@nawana.app", "https://ig.me/m/nawana.app"]
const SUBJECT = "지원서 잘 받았습니다"

const INK = "#141310", PAPER = "#FCFBF8", SURF = "#F0EFE9", FAINT = "#918E85", BLUE = "#0A5CF5"
const FONT = "'Helvetica Neue',Helvetica,-apple-system,'Apple SD Gothic Neo',Arial,sans-serif"
const MONO = "ui-monospace,'SF Mono',Menlo,'Roboto Mono',monospace"

const esc = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")

type Kind = "creator" | "challenger"

// The fee follows where the applicant lives, the page's rule: won in Korea,
// yen in Japan, euro where the euro is money, dollars everywhere else.
const EUROZONE = new Set(["AT","BE","BG","CY","DE","EE","ES","FI","FR","GR","HR","IE","IT","LT","LU","LV","MT","NL","PT","SI","SK","AD","MC","SM","VA","ME","XK"])
// Countries the App Store prices in their own money: [currency, three months]. The page's LOCAL_FEE, the same figures.
const LOCAL_FEE: Record<string, [string, number]> = { AE: ["aed", 107.97], AU: ["aud", 40.47], BR: ["brl", 161.73], CA: ["cad", 35.07], CH: ["chf", 24], CL: ["clp", 26973], CN: ["cny", 183], CO: ["cop", 134730], CZ: ["czk", 672], DK: ["dkk", 240], EG: ["egp", 1349.97], GB: ["gbp", 26.97], HK: ["hkd", 237], HU: ["huf", 12123], ID: ["idr", 456300], IL: ["ils", 94.23], IN: ["inr", 2697], KZ: ["kzt", 16173], MX: ["mxn", 537], MY: ["myr", 134.73], NG: ["ngn", 40230], NO: ["nok", 348], NZ: ["nzd", 53.97], PE: ["pen", 121.23], PH: ["php", 1617], PK: ["pkr", 7830], PL: ["pln", 134.97], QA: ["qar", 107.97], RO: ["ron", 134.97], SA: ["sar", 107.97], SE: ["sek", 348], SG: ["sgd", 40.44], TH: ["thb", 1077], TR: ["try", 1349.97], TW: ["twd", 864], TZ: ["tzs", 80730], VN: ["vnd", 807300], ZA: ["zar", 539.97] }
function fee(country: string | null, lang: Lang = "ko"): { cur: string; label: string } {
  if (lang === "en") return feeEn(country)
  const local = country ? LOCAL_FEE[country] : undefined
  if (local) {
    const [cur, amount] = local
    let label = `${cur.toUpperCase()} ${amount}`
    try { label = new Intl.NumberFormat("en-US", { style: "currency", currency: cur.toUpperCase(), minimumFractionDigits: Number.isInteger(amount) ? 0 : 2, maximumFractionDigits: 2 }).format(amount) } catch { /* the code and the number */ }
    return { cur, label: label + " " }
  }
  if (country === "KR" || !country) return { cur: "krw", label: "40,500원" }
  if (country === "JP") return { cur: "jpy", label: "4,050엔" }
  return EUROZONE.has(country) ? { cur: "eur", label: "26.97유로" } : { cur: "usd", label: "26.97달러" }
}
// The same money as fee(), written the English way: "₩40,500", "¥4,050", "€26.97", "$26.97", "CA$35.07".
// One difference: no country is dollars here, the English page's "anywhere without its own App Store price".
function feeEn(country: string | null): { cur: string; label: string } {
  const local = country ? LOCAL_FEE[country] : undefined
  const [cur, amount]: [string, number] = local ?? (
    country === "KR" ? ["krw", 40500]
    : !country ? ["usd", 26.97]
    : country === "JP" ? ["jpy", 4050]
    : EUROZONE.has(country) ? ["eur", 26.97] : ["usd", 26.97])
  try {
    return { cur, label: new Intl.NumberFormat("en-US", { style: "currency", currency: cur.toUpperCase(), minimumFractionDigits: Number.isInteger(amount) ? 0 : 2, maximumFractionDigits: 2 }).format(amount) }
  } catch {
    return { cur, label: `${cur.toUpperCase()} ${amount}` }
  }
}

interface Copy {
  subject: string; hi: string; body: string[]; button: [string, string] | null
  useHead: string; use: string[]
  /** A challenger's application is not complete until these two are done: the mail leads with them. */
  finish?: { head: string; one: string; two: string; pay: [string, string]; notes: string[] }
  after: string[]; scheduleHead: string; schedule: [string, string][]; scheduleNote: string
  askHead: string; ask: string; thanks: string; sign: string; foot: string
  /** The words the layout itself carries: the store buttons, the reply row, the banner, the page it links back to. */
  ui: { ios: string; android: string; iosText: string; androidText: string; reply: string; bannerAlt: string; page: string
    /** The banner image under SITE, or null for a mail with no banner. */
    banner: string | null }
}

const UI_KO: Copy["ui"] = {
  ios: "아이폰에서 받기", android: "안드로이드에서 받기", iosText: "아이폰", androidText: "안드로이드",
  reply: "이 메일에 답장", bannerAlt: "nawana Creator program 1기 · 우리의 가장 뜨거울 100일", page: "/creators",
  banner: "/mail/creator-banner.jpg",
}
const UI_EN: Copy["ui"] = {
  ios: "Get it on iPhone",
  android: "Get it on Android",
  iosText: "iPhone",
  androidText: "Android",
  reply: "Reply to this email",
  bannerAlt: "nawana Creator Program · Cohort 1 · 100 days, all in",
  page: "/en/creators",
  // The Korean banner has Hangul on it: no banner until an English one exists in web/mail/ (then its path here).
  banner: null,
}

// The dates are cohort 1's and are the page's: program/RULES.md.
function lines(name: string, kind: Kind, applicationId: string | null, country: string | null = null, lang: Lang = "ko"): Copy {
  if (lang === "en") return linesEn(name, kind, applicationId, country)
  const common = {
    ui: UI_KO,
    hi: `${name}님, 안녕하세요. 나와나를 만드는 이응규입니다.`,
    scheduleHead: "다음 일정",
    scheduleNote: "지원 인원에 따라 일정이 변경될 수 있습니다. 바뀌면 이 메일 주소로 먼저 알려드리겠습니다.",
    useHead: "기다리는 동안 할 일",
    askHead: "궁금한 점이 있다면",
    ask: "이 메일에 답장하시거나 스레드, 인스타그램 DM으로 편하게 보내주세요. 제가 직접 읽고 답합니다.",
    sign: "이응규 드림",
  }
  if (kind === "challenger") {
    const price = fee(country)
    const pay = `${SITE}/pay${applicationId ? "?id=" + applicationId + "&cur=" + price.cur : ""}`
    return {
      ...common,
      subject: "100일 챌린지, 가입과 결제를 마쳐주세요",
      body: [
        "100일 챌린지 1기 신청서 잘 받았습니다.",
        "신청은 아래 두 가지를 마쳐야 완료됩니다.",
      ],
      button: null, after: [], use: [],
      finish: {
        head: "신청을 마치려면",
        one: "나와나 앱을 받고 가입합니다. 이미 쓰고 계시다면 넘어가셔도 됩니다.",
        two: "앱에서 가입한 방법(Apple 또는 Google)으로 로그인해 결제합니다.",
        pay: ["결제하러 가기", pay],
        notes: [
          `참가비는 Light 3개월 구독료 ${price.label.endsWith(" ") ? price.label + "로" : price.label + "이고"}, 한 번만 결제됩니다. 결제 화면에서 Plus나 Max도 고르실 수 있습니다. 마지막 10일은 제가 무료로 드립니다.`,
          "결제하신 날부터 앱을 쓰실 수 있습니다. Light는 한 달에 통화 150분입니다. 시작 전에 꼭 써보세요.",
          "시작하기 전에는 전액 환불해 드립니다. 시작한 뒤에도 결제하신 날부터 14일 안에는 취소하실 수 있습니다. 이 메일에 답장해 주세요.",
          "이미 나와나를 구독하고 계시다면 결제하지 마시고 이 메일에 답장해 주세요.",
        ],
      },
      schedule: [
        ["11월 19일까지", "가입과 결제"],
        ["12월 1일 (예정)", "100일 시작"],
        ["3월 10일 (예정)", "100일 끝"],
        ["그다음 날부터", "지킨 달 수만큼 이어서 무료"],
      ],
      thanks: "신청해 주셔서 고맙습니다.",
      foot: "이 메일은 100일 챌린지에 신청하셨을 때 한 번 발송됩니다.",
    }
  }
  return {
    ...common,
    subject: SUBJECT,
    body: [
      "크리에이터 프로그램 1기 지원서 잘 받았습니다. 적어주신 내용은 제가 전부 직접 읽습니다.",
      "읽고 나서 이 메일 주소나 남겨주신 연락처로 다시 연락드리겠습니다.",
    ],
    button: null,
    use: [
      "기다리는 동안 나와나를 꼭 써보세요. 어떤 100일을 보낼지는 직접 써봐야 보입니다.",
      "오늘 첫 통화부터 해보세요. 처음 20분은 무료입니다.",
    ],
    after: [
      "지원서에서 고치고 싶은 부분이 있으면 11월 19일까지 같은 연락처로 한 번 더 보내주시면 됩니다. 제가 읽기 전이라면 새 내용으로 바뀝니다. 그 뒤에는 이 메일에 답장해 주세요.",
    ],
    schedule: [
      ["11월 19일까지", "지원서 접수"],
      ["11월 중", "제가 읽고 연락"],
      ["11월 말", "올릴 일정 정하고 코드 전달"],
      ["12월 1일 (예정)", "100일 시작"],
      ["3월 10일 (예정)", "100일 끝"],
    ],
    thanks: "지원해주셔서 고맙습니다.",
    foot: "이 메일은 크리에이터 프로그램에 지원하셨을 때 한 번 발송됩니다.",
  }
}

// The English page's mail: the same structure as the Korean one above, its own words.
function linesEn(name: string, kind: Kind, applicationId: string | null, country: string | null = null): Copy {
  const common = {
    ui: UI_EN,
    hi: `Hi ${name}, I'm Eunggyu, and I make nawana.`,
    scheduleHead: "What happens next",
    scheduleNote: "These dates are planned and may change with the number of applicants. If they do, I'll tell you at this address first.",
    useHead: "While you wait",
    askHead: "Questions?",
    ask: "Just reply to this email, or send me a DM on Threads or Instagram. I read and answer every one myself.",
    sign: "Eunggyu",
  }
  if (kind === "challenger") {
    const price = fee(country, "en")
    const pay = `${SITE}/pay?${applicationId ? "id=" + applicationId + "&cur=" + price.cur + "&" : ""}lang=en`
    return {
      ...common,
      subject: "Finish signing up: join the app and pay",
      body: [
        "I got your form for cohort 1 of the 100-day challenge.",
        "Two steps below, and you're in.",
      ],
      button: null, after: [], use: [],
      finish: {
        head: "To finish signing up",
        one: "Get the nawana app and sign up. If you already use it, skip this step.",
        two: "Sign in the way you signed up in the app (Apple or Google), and pay.",
        pay: ["Go to payment", pay],
        notes: [
          `The fee is three months of Light, ${price.label}, charged once. You can pick Plus or Max on the payment page instead. The last 10 days are on me.`,
          "You can use the app from the day you pay. Light gives you 150 minutes of calls a month. Start using it now, before day 1.",
          "Before day 1, you can get a full refund. After that, you can still cancel within 14 days of paying. Just reply to this email.",
          "If you already subscribe to nawana, please don't pay. Reply to this email instead.",
        ],
      },
      schedule: [
        ["By Nov 19", "Join the app and pay"],
        ["Dec 1 (planned)", "Day 1 of 100"],
        ["Mar 10 (planned)", "Day 100"],
        ["From the next day", "Free months, one for each month you kept"],
      ],
      thanks: "Thanks for taking this on with me.",
      foot: "You get this email once, when you sign up for the 100-day challenge.",
    }
  }
  return {
    ...common,
    subject: "I got your application",
    body: [
      "Thank you for applying to cohort 1 of the nawana Creator Program. I read every word of every application myself.",
      "Once I've read yours, I'll get back to you here or at the handle you left.",
    ],
    button: null,
    use: [
      "Start using nawana now, while you wait. You'll only see what your 100 days could look like once you've tried it.",
      "Make your first call today. Your first 20 minutes are free.",
    ],
    after: [
      "Want to change something in your application? Send the form again with the same email address by November 19. If I haven't read it yet, the new one replaces it. After that, just reply to this email.",
    ],
    schedule: [
      ["By Nov 19", "Applications close"],
      ["During November", "I read yours and get in touch"],
      ["Late November", "We set your posting days, and I send your code"],
      ["Dec 1 (planned)", "Day 1 of 100"],
      ["Mar 10 (planned)", "Day 100"],
    ],
    thanks: "Thank you for applying.",
    foot: "You get this email once, when you apply to the nawana Creator Program.",
  }
}

function html(c: Copy): string {
  const p = (s: string, top = 14) =>
    `<p style="font-size:16px;line-height:1.7;color:${INK};margin:${top}px 0 0;">${s}</p>`
  const head = (s: string) =>
    `<p style="font-size:13px;letter-spacing:.04em;color:${FAINT};margin:34px 0 0;font-family:${MONO};">${s}</p>`
  const cell = `padding:13px 0;border-bottom:1px solid ${SURF};`
  const row = (left: string, right: string, href: string) =>
    `<tr><td style="${cell}font-size:15px;"><a href="${href}" style="color:${INK};text-decoration:none;">${left}</a></td>` +
    `<td align="right" style="${cell}font-size:14px;"><a href="${href}" style="color:${BLUE};text-decoration:none;">${right}</a></td></tr>`
  const when = (left: string, right: string) =>
    `<tr><td style="${cell}font-size:14px;color:${FAINT};white-space:nowrap;padding-right:16px;">${left}</td>` +
    `<td style="${cell}font-size:15px;color:${INK};">${right}</td></tr>`
  const table = (rows: string) =>
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:14px 0 0;border-top:1px solid ${SURF};">${rows}</table>`
  const pill = (label: string, href: string, solid = false) =>
    `<a href="${href}" style="display:inline-block;border:1px solid ${INK};background:${solid ? INK : "transparent"};color:${solid ? PAPER : INK};text-decoration:none;font-size:14px;font-weight:600;padding:9px 16px;border-radius:999px;margin:0 6px 6px 0;">${label}</a>`
  const step = (n: number, left: string, right: string) =>
    `<tr><td style="${cell}font-size:13px;color:${FAINT};font-family:${MONO};width:22px;">${n}</td>` +
    `<td style="${cell}font-size:15px;color:${INK};"><b>${right}</b><br><span style="font-size:14px;color:${FAINT};">${left}</span></td></tr>`
  const body = [
    p(c.hi, 0), ...c.body.map((s) => p(s)),
    c.button ? `<p style="margin:18px 0 0;">${pill(c.button[0], c.button[1], true)}</p>` : "",
    ...c.after.map((s, i) => p(s, i === 0 ? 22 : 14)),
    ...(c.finish ? [
      head(c.finish.head),
      p(`<b>1.</b> ${c.finish.one}`, 10),
      `<p style="margin:12px 0 0;">${pill(c.ui.ios, APP_STORE)}${pill(c.ui.android, PLAY_STORE)}</p>`,
      p(`<b>2.</b> ${c.finish.two}`, 18),
      `<p style="margin:12px 0 0;">${pill(c.finish.pay[0], c.finish.pay[1], true)}</p>`,
      ...c.finish.notes.map((s, i) => `<p style="font-size:14px;line-height:1.7;color:${FAINT};margin:${i === 0 ? 18 : 6}px 0 0;">${s}</p>`),
    ] : [
      head(c.useHead),
      ...c.use.map((s, i) => p(s, i === 0 ? 10 : 8)),
      `<p style="margin:16px 0 0;">${pill(c.ui.ios, APP_STORE, true)}${pill(c.ui.android, PLAY_STORE, true)}</p>`,
    ]),
    head(c.scheduleHead),
    table(c.schedule.map(([l, r], i) => step(i + 1, l, r)).join("")),
    `<p style="font-size:13px;line-height:1.7;color:${FAINT};margin:10px 0 0;">${c.scheduleNote}</p>`,
    head(c.askHead),
    p(c.ask, 10),
    table(row(c.ui.reply, REPLY_TO, `mailto:${REPLY_TO}`) +
      row("Threads", `${THREADS[0]} →`, THREADS[1]) +
      row("Instagram DM", `${INSTAGRAM[0]} →`, INSTAGRAM[1])),
    p(c.thanks, 30), p(c.sign, 22),
  ].join("")
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:${PAPER};">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${PAPER};padding:40px 20px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;"><tr><td style="font-family:${FONT};color:${INK};">
${c.ui.banner ? `<a href="${SITE}${c.ui.page}" style="display:block;margin:0 0 30px;"><img src="${SITE}${c.ui.banner}" width="480" alt="${c.ui.bannerAlt}" style="display:block;width:100%;max-width:480px;height:auto;border:0;"></a>
` : ""}${body}
<div style="margin-top:40px;padding-top:18px;border-top:1px solid ${SURF};font-size:12px;line-height:1.7;color:${FAINT};">
<a href="${SITE}${c.ui.page}" style="color:${FAINT};text-decoration:none;">nawana.app${c.ui.page}</a> &nbsp;·&nbsp;
<a href="mailto:${REPLY_TO}" style="color:${FAINT};text-decoration:none;">${REPLY_TO}</a><br>Dear RoRo · Munich<br>${c.foot}</div>
</td></tr></table></td></tr></table></body></html>`
}

function text(c: Copy): string {
  return [
    c.hi, ...c.body, ...(c.button ? [`${c.button[0]}: ${c.button[1]}`] : []), ...c.after,
    ...(c.finish ? [
      `[${c.finish.head}]`,
      `1. ${c.finish.one}\n${c.ui.iosText}: ${APP_STORE}\n${c.ui.androidText}: ${PLAY_STORE}`,
      `2. ${c.finish.two}\n${c.finish.pay[0]}: ${c.finish.pay[1]}`,
      ...c.finish.notes,
    ] : [`[${c.useHead}]`, ...c.use, `${c.ui.iosText}: ${APP_STORE}\n${c.ui.androidText}: ${PLAY_STORE}`]),
    `[${c.scheduleHead}]`, c.schedule.map(([l, r], i) => `${i + 1}. ${r} · ${l}`).join("\n"), c.scheduleNote,
    `[${c.askHead}]`, c.ask,
    `${c.ui.reply}: ${REPLY_TO}\nThreads: ${THREADS[1]}\nInstagram DM: ${INSTAGRAM[1]}`,
    c.thanks, c.sign, c.foot,
  ].join("\n\n")
}

/** Sends the "we have it" mail. Never throws; says whether it went. */
export async function sendReceived(
  to: string, name: string, kind: Kind = "creator", applicationId: string | null = null, country: string | null = null,
  lang: Lang = "ko",
): Promise<boolean> {
  const en = lang === "en"
  const where = /^[A-Z]{2}$/.test(country ?? "") ? country : null
  const key = Deno.env.get("RESEND_API_KEY")
  if (!key) { console.warn("creator mail: RESEND_API_KEY unset, nothing sent"); return false }
  const who = name.trim().slice(0, 60) || (en
    ? "there"
    : (kind === "challenger" ? "신청자" : "지원자"))
  // The id goes into a link: only a uuid is let through.
  const id = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(applicationId ?? "") ? applicationId : null
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: FROM[lang], to: [to], reply_to: REPLY_TO, subject: lines(who, kind, id, where, lang).subject,
        html: html(lines(esc(who), kind, id, where, lang)), text: text(lines(who, kind, id, where, lang)),
        tags: [{ name: "campaign", value: (kind === "challenger" ? "challenger-received" : "creator-received") + (en ? "-en" : "") }],
      }),
    })
    if (!res.ok) console.error("creator mail failed", res.status, (await res.text()).slice(0, 200))
    return res.ok
  } catch (err) {
    console.error("creator mail threw", err instanceof Error ? err.message : String(err))
    return false
  }
}
