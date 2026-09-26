import { TIER_LIST, type Truth } from "./truth";

// Turn admin_raw()'s raw aggregates into the shape the page draws.
//
// This is gather_admin.py + derive_cost.py, in JS. The split is deliberate:
// SQL returns rows, this file decides indices, origins and economics, and the
// page renders. Moving any of it into SQL would put the page's layout in the
// database; moving it into SQL's caller in Python again would mean the live
// page and the snapshot disagree about the same day.

// The owner is a REAL user of the product, not a test fixture — he practises
// on it daily, and his account is the only one with enough metered talk to
// derive a cost per minute from. So he is included everywhere by default and
// merely marked. Only the synthetic device-test account is filtered, and that
// one is genuinely not a person.
const OWNER_ID = "72bcaa7e-3dd2-4364-b197-078ba59c1ce4";
const TEST_IDS = new Set([
  "ecd78251-49c4-4e18-a156-6fbe90fd6e3b",
  // The owner's own Google test accounts (2026-09-21) — signed up like a
  // stranger to walk the onboarding and the free first call.
  "c5a85f25-a631-47c5-b32b-fb5bc89c551e",
  "5692cfc2-13ec-4f7e-a3bc-31daee02e28f",
  // The owner's second device (2026-09-23) — the private-relay Apple account
  // re-created on 2026-09-16 that carries the admin flag. Its 09-15
  // predecessor (c7565d27-…) was already flagged; this id replaced it.
  "b28ca7b1-dbd8-46de-bfd2-5857e05665bc",
]);

// Apple's cut and the sticker prices. Prices live in docs/launch-billing.md;
// they are NOT in the database (there is no price column), so they are stated
// here and nowhere else in this pipeline.
// The US list price, which is what the margin table is computed in. Keep it
// equal to App Store Connect — nothing reads ASC from here, so a stale figure
// silently mis-states every margin on the page. Plus went to $24.99 on
// 2026-09-26; the annuals are off sale (`20260926160000`) and stay listed
// only so a historical month still prices.
const MONTHLY_PRICE: Record<string, number> = {
  light_monthly: 9.99,
  light_annual: 79.99 / 12,
  plus_monthly: 24.99,
  plus_annual: 143.99 / 12,
};
// Credits per character come from the model, not the plan: multilingual_v2
// bills 1.0 credit/char, turbo and flash 0.5. Since 2026-09-26 every
// clone-voice surface is turbo (`ElevenLabsClient.cloneModelId`), so the
// fidelity rate applies to history only.
const CREDITS_PER_CHAR = { fidelity: 1.0, conversation: 0.5 };

// The same catalog per storefront (docs/launch-billing.md §1 — ASC values,
// KRW set by hand). What lands in the bank differs by store: the US price
// carries no VAT (net = price × 85%), Korea's includes 10% VAT and Apple
// takes its cut after it (77.3%), Germany's includes 19%. The 돈 tab's unit
// economics quote the average of the three, in EUR.
const STORE_PRICES: Record<string, { USD: number; KRW: number; EUR: number; months: number }> = {
  light_monthly: { USD: 9.99,   KRW: 15_000,  EUR: 9.99,   months: 1 },
  light_annual:  { USD: 79.99,  KRW: 110_000, EUR: 89.99,  months: 12 },
  plus_monthly:  { USD: 19.99,  KRW: 29_000,  EUR: 22.99,  months: 1 },
  plus_annual:   { USD: 143.99, KRW: 209_000, EUR: 149.99, months: 12 },
};
const VAT = { KR: 0.10, DE: 0.19 };

// Infrastructure that bills whether or not anyone talks, USD per month. The
// ElevenLabs plan fee is NOT here — the calculator picks the tier from the
// credits a scenario needs. People, tax and marketing are nobody's line item
// here either: "순이익" on the tab is gross margin minus these.
const FIXED_USD = { supabase: 25, cloudflare: 5, apple: 99 / 12 };


// Purposes whose TTS is review material (free behind daily caps), all turbo.
const REVIEW_PURPOSES = new Set(["shadow", "drill", "library", "voice_preview"]);
const isTurbo = (m: string) => m !== "eleven_multilingual_v2" && m !== "eleven_v3";

/** The 돈 tab's 실제 원가 + 단위 경제 block, built from ElevenLabs' own
 *  numbers with the ledger beside them. Every "recorded" figure is what
 *  `usage_ledger` knows; every total is what ElevenLabs billed. */
function buildEcon(t: Truth, w: { talkMin: number; scenes: number; gmUsd: number; days: number;
                                  signups: number; commission: number; rateDb: number }) {
  const bp = t.ledger?.byPurpose ?? {};
  const sum = (pred: (purpose: string, model: string) => boolean) =>
    Object.entries(bp).reduce((a, [k, v]) => a + (pred(k.split("|")[0], v.model) ? v.credits : 0), 0);
  const rowsOf = (purpose: string) =>
    Object.entries(bp).reduce((a, [k, v]) => a + (k.split("|")[0] === purpose ? v.rows : 0), 0);

  const ledTurn = sum((p, m) => p === "turn" && isTurbo(m));
  const ledTurboNonTurn = sum((p, m) => p !== "turn" && isTurbo(m));
  const ledSceneTurbo = sum((p, m) => p === "scene" && isTurbo(m));
  const ledSceneFid = sum((p, m) => p === "scene" && !isTurbo(m));
  const ledVm = sum((p) => p === "daily-call");
  const ledReview = sum((p) => REVIEW_PURPOSES.has(p));
  const ledMulti = sum((_p, m) => m === "eleven_multilingual_v2");
  const ledOtherTurbo = Math.max(0, ledTurboNonTurn - ledSceneTurbo - ledVm - ledReview);
  const ledOtherMulti = Math.max(0, ledMulti - ledSceneFid);
  const ledTotal = t.ledger?.total ?? 0;

  const M = t.models;
  const el = (k: string) => M[k] ?? 0;
  const elTurbo = el("eleven_turbo_v2_5") + el("eleven_flash_v2_5");
  const elMulti = el("eleven_multilingual_v2");
  const elTtv = Object.entries(M).filter(([k]) => k.startsWith("eleven_ttv")).reduce((a, [, v]) => a + v, 0);
  const elV3 = el("eleven_v3");
  const elTotal = Object.values(M).reduce((a, v) => a + v, 0);
  const elOther = elTotal - elTurbo - elMulti - elTtv - elV3;

  // Talk TTS = every turbo credit ElevenLabs saw minus the turbo credits the
  // ledger attributes to something that is not a turn. What's left over the
  // ledger's own turn rows is the gateway's unrecorded share.
  const talk = Math.max(0, elTurbo - ledTurboNonTurn);
  const gatewayGap = Math.max(0, talk - ledTurn);
  const multiGap = Math.max(0, elMulti - ledMulti);

  const cats = [
    { key: "talk", label: "통화 TTS", credits: talk, recorded: "partial",
      note: `원장 ${Math.round(ledTurn).toLocaleString("en-US")} · 게이트웨이 ${Math.round(gatewayGap).toLocaleString("en-US")} 미기록` },
    { key: "scene", label: "Watch 장면", credits: ledSceneTurbo + ledSceneFid, recorded: "yes",
      note: `${w.scenes}장면 · 클론 절반은 v2, 상대역은 turbo` },
    { key: "vm", label: "일일 통화 보이스메일", credits: ledVm, recorded: "yes",
      note: `${rowsOf("daily-call")}회 합성` },
    { key: "accent", label: "악센트 미리듣기 (text-to-voice)", credits: elTtv, recorded: "no",
      note: "횟수만 기록, 크레딧 없음" },
    { key: "review", label: "복습 (섀도잉·드릴·라이브러리·미리듣기)", credits: ledReview, recorded: "yes", note: "" },
    { key: "onb", label: "온보딩 인사 등 (v2, 미기록분)", credits: multiGap, recorded: "no", note: "" },
    { key: "misc_rec", label: "기타 (기록됨)", credits: ledOtherTurbo + ledOtherMulti, recorded: "yes", note: "" },
    { key: "v3", label: "eleven_v3 (경로 미확인)", credits: elV3, recorded: "no", note: "" },
    { key: "other", label: "그 외 모델 (STT 등)", credits: elOther, recorded: "no", note: "" },
  ].filter((c) => c.credits > 0.5)
   .map((c) => ({ ...c, credits: Math.round(c.credits), share: elTotal ? c.credits / elTotal : 0 }));

  const usdToEur = 1 / t.fx.USD;
  const eurPerCredit = t.rate * usdToEur;
  const talkCreditsPerMin = w.talkMin > 0 ? talk / w.talkMin : 0;
  const gmEurPerMin = w.talkMin > 0 ? (w.gmUsd / w.talkMin) * usdToEur : 0;
  const sceneCredits = w.scenes > 0 ? (ledSceneTurbo + ledSceneFid) / w.scenes : 0;
  const vmPerSynth = rowsOf("daily-call") ? ledVm / rowsOf("daily-call") : 0;
  const onboardingCredits = w.signups > 0 ? (elTtv + multiGap + ledOtherMulti) / w.signups : 0;
  const freeMinutes = 10;

  const byDay = t.days.map((d) => ({
    d: d.d,
    actual: Math.round(Object.values(d.models).reduce((a, v) => a + v, 0)),
    recorded: Math.round(t.ledger?.byDay[d.d] ?? 0),
  }));

  // What a subscriber leaves in the bank, per store, EUR per month.
  const net = (planId: string) => {
    const p = STORE_PRICES[planId];
    const us = p.USD * (1 - w.commission) * usdToEur;
    const kr = (p.KRW / (1 + VAT.KR)) * (1 - w.commission) / t.fx.KRW;
    const de = (p.EUR / (1 + VAT.DE)) * (1 - w.commission);
    const avg = (us + kr + de) / 3;
    const per = (v: number) => round(v / p.months, 2);
    return { US: per(us), KR: per(kr), DE: per(de), avg: per(avg) };
  };
  const plans = Object.keys(STORE_PRICES).map((id) => ({ id, net: net(id), months: STORE_PRICES[id].months }));

  const fixedUsd = FIXED_USD.supabase + FIXED_USD.cloudflare + FIXED_USD.apple;
  const cycleDays = t.cycle.startedAt ? Math.max(1, (Date.now() - Date.parse(t.cycle.startedAt)) / 86_400_000) : w.days;

  return {
    fetchedAt: t.fetchedAt,
    tier: t.tier, tierPrice: t.tierPrice, tierCredits: t.tierCredits,
    rate: t.rate, rateDb: w.rateDb, eurPerCredit: round(eurPerCredit, 8),
    fx: t.fx,
    cycle: { used: t.cycle.used, limit: t.cycle.limit, resetAt: t.cycle.resetAt,
             perDay: round(t.cycle.used / cycleDays), per30: round(t.cycle.used / cycleDays * 30) },
    window: { start: t.windowStart, days: w.days, credits: Math.round(elTotal),
              recorded: Math.round(ledTotal), recordedShare: elTotal ? round(ledTotal / elTotal, 3) : null,
              elEur: round(elTotal * eurPerCredit, 2), gmEur: round(w.gmUsd * usdToEur, 2),
              talkMin: round(w.talkMin, 1), scenes: w.scenes, signups: w.signups,
              perDayEur: round((elTotal * eurPerCredit + w.gmUsd * usdToEur) / Math.max(1, w.days), 2) },
    cats, byDay,
    unit: {
      talkCreditsPerMin: round(talkCreditsPerMin, 1),
      talkEurPerMin: round(talkCreditsPerMin * eurPerCredit + gmEurPerMin, 4),
      gmEurPerMin: round(gmEurPerMin, 4),
      sceneCredits: round(sceneCredits), sceneEur: round(sceneCredits * eurPerCredit, 3),
      vmPerSynth: round(vmPerSynth), vmCreditsPerSubMonth: round(vmPerSynth * 30),
      vmEurPerSubMonth: round(vmPerSynth * 30 * eurPerCredit, 2),
      onboardingCredits: round(onboardingCredits),
      signupCredits: round(onboardingCredits + freeMinutes * talkCreditsPerMin),
      signupEur: round((onboardingCredits + freeMinutes * talkCreditsPerMin) * eurPerCredit + freeMinutes * gmEurPerMin, 2),
      freeMinutes,
    },
    plans,
    tiers: TIER_LIST,
    fixed: { usd: round(fixedUsd, 2), eur: round(fixedUsd * usdToEur, 2), items: FIXED_USD },
    ledgerOk: !!t.ledger,
  };
}

const round = (v: number, d = 0) => {
  const m = Math.pow(10, d);
  return Math.round(v * m) / m;
};

function daysBetween(start: string, today: string): string[] {
  const out: string[] = [];
  const end = Date.parse(today + "T00:00:00Z");
  for (let t = Date.parse(start + "T00:00:00Z"); t <= end; t += 86400000) {
    out.push(new Date(t).toISOString().slice(0, 10));
  }
  return out;
}

// One word for what a subscription is DOING. `status` alone can't tell a
// trial that was cancelled an hour after it started from one still running
// (both are "trialing"), and a comp is not a sale. Used by the launch tab's
// funnel and by every plan chip on the page.
function subStateOf(u: any): string {
  if (!u.plan_id) return "none";
  if (u.sub_source === "comp") return u.sub_status === "active" ? "comp" : u.sub_status;
  if (u.sub_status === "trialing") return u.cancel_at_period_end ? "trial_cancelled" : "trial";
  if (u.sub_status === "active") return u.cancel_at_period_end ? "cancelling" : "paid";
  return u.sub_status;   // expired, past_due, … verbatim
}

const deviceOf = (ua: string | null) =>
  !ua ? null : ua.includes("iPhone") ? "iPhone" : ua.includes("iPad") ? "iPad" : null;

export function assemble(raw: any, truth: Truth | null = null) {
  const days = daysBetween(raw.windowStart, raw.today);
  const dayIdx = new Map<string, number>(days.map((d, i) => [d, i]));
  const uidx = new Map<string, number>(raw.users.map((u: any, i: number) => [u.id, i]));

  const idx = (r: any) => uidx.get(r.id);
  const keep = (r: any) => uidx.has(r.id) && dayIdx.has(r.d);

  // [user, day, rows, turns, talk secs, learner-speech secs | null]. The last
  // is null wherever no tick measured it (before 2026-09-21, or the classic
  // path) — never 0, which would claim they said nothing.
  const cells = raw.cells.filter(keep).map((r: any) =>
    [idx(r), dayIdx.get(r.d), r.rows, r.turns, r.secs, r.spoke ?? null]);
  const sceneCells = raw.scenes.filter(keep).map((r: any) =>
    [idx(r), dayIdx.get(r.d), r.n]);
  const sessions = raw.sessions.filter(keep).map((r: any) =>
    [idx(r), dayIdx.get(r.d), r.secs]);
  const errorsDaily = raw.errors
    .filter((r: any) => dayIdx.has(r.d))
    .map((r: any) => [dayIdx.get(r.d), r.n]);

  // ---------------------------------------------------------------- users
  const agg = new Map<number, { days: Set<number>; turns: number; secs: number;
                                spoke: number | null; spokeOf: number }>();
  for (const c of cells) {
    const a = agg.get(c[0]) ?? { days: new Set<number>(), turns: 0, secs: 0,
                                 spoke: null, spokeOf: 0 };
    a.days.add(c[1]); a.turns += c[3]; a.secs += c[4];
    // `spokeOf` is the talk time on the SAME days speech was measured, so a
    // share is never learner seconds from one week over billed seconds from
    // three.
    if (c[5] !== null) { a.spoke = (a.spoke ?? 0) + c[5]; a.spokeOf += c[4]; }
    agg.set(c[0], a);
  }
  const sceneTot = new Map<number, number>();
  for (const s of sceneCells) sceneTot.set(s[0], (sceneTot.get(s[0]) ?? 0) + s[2]);
  const sessCt = new Map<number, number>();
  for (const s of sessions) sessCt.set(s[0], (sessCt.get(s[0]) ?? 0) + 1);

  const langByUser = new Map<string, string[]>(
    raw.langs.map((l: any) => [l.id, l.langs]));

  const users = raw.users.map((u: any, i: number) => {
    const a = agg.get(i) ?? { days: new Set<number>(), turns: 0, secs: 0,
                              spoke: null, spokeOf: 0 };
    const ds = [...a.days].sort((x, y) => x - y);
    const rv = raw.reviews
      .filter((r: any) => r.id === u.id)
      .map((r: any) => ({ context: r.context, rating: r.rating, body: r.body,
                          d: r.d, at: r.at ?? null }));
    // Someone who signed up before the cutover is only observed from it, so
    // streaks and week-N retention must be counted from there — not from a
    // signup date whose first weeks this page cannot see.
    const preWindow = u.signed_up < raw.windowStart;
    return {
      id: u.id,
      label: u.display_name || (u.email ? u.email.split("@")[0] : u.id.slice(0, 8)),
      email: u.email,
      dev: TEST_IDS.has(u.id),
      owner: u.id === OWNER_ID,
      // Not a signup: an onboarding session that never reached Apple sign-in
      // (field absent until 20260923110000 is applied → false).
      anonymous: !!u.anonymous,
      signedUp: u.signed_up,
      origin: preWindow ? raw.windowStart : u.signed_up,
      preWindow,
      plan: u.plan_id, subStatus: u.sub_status, trialEnds: u.trial_ends,
      balance: u.balance, clone: u.clone,
      activeDays: ds.length,
      firstActive: ds.length ? days[ds[0]] : null,
      lastActive: ds.length ? days[ds[ds.length - 1]] : null,
      turns: a.turns, talkSecs: a.secs,
      spokeSecs: a.spoke, spokeOfSecs: a.spokeOf,
      talkSessions: sessCt.get(i) ?? 0, scenes: sceneTot.get(i) ?? 0,
      reviewCount: rv.length, langs: langByUser.get(u.id) ?? [],
      name: u.display_name, realEmail: u.real_email,
      occupation: u.occupation, location: u.location,
      interests: u.interests, intro: u.intro,
      channel: u.channel, device: deviceOf(u.user_agent),
      // The clone they are USING — its ElevenLabs name and id, which is the
      // only handle that matches a row here to the ElevenLabs dashboard.
      voiceName: u.voice_name ?? null,
      voiceId: u.voice_id ?? null,
      voiceAt: u.voice_at ?? null,
      waitlistAt: u.waitlist_at, reviews: rv,
      // launch watch (2026-09-12) — timestamps, not dates, because on a
      // launch day "when" is an hour, not a date
      signedUpAt: u.signed_up_at ?? null,
      provider: u.provider ?? null,
      lastSignIn: u.last_sign_in_at ?? null,
      cloneAt: u.clone_at ?? null,
      firstTalkAt: u.first_talk_at ?? null,
      lastTalkAt: u.last_talk_at ?? null,
      subState: subStateOf(u),
      subSource: u.sub_source ?? null,
      subStartedAt: u.sub_started ?? null,
      periodEnd: u.period_end ?? null,
      trialEndsAt: u.trial_ends_at ?? null,
      cancelAtPeriodEnd: !!u.cancel_at_period_end,
    };
  });

  // ---------------------------------------------------------------- launch
  // Everything here is keyed by user INDEX like the cells are, and every
  // list is optional on the raw side so a Worker deployed ahead of the
  // migration (or the offline snapshot, whose Python gather doesn't emit
  // these) renders the tab empty instead of failing to render at all.
  const withIdx = (rows: any[] | undefined) =>
    (rows ?? []).filter((r: any) => uidx.has(r.id))
      .map((r: any) => ({ ...r, u: uidx.get(r.id) }));
  const subEvents = withIdx(raw.sub_events);
  const recentSessions = withIdx(raw.recent_sessions);
  const recentEvents = withIdx(raw.recent_events);
  const freeRecent = withIdx(raw.free_recent);
  // One row per finished realtime call. This is the only per-call record
  // that path produces — its reply and voice never touch the usage ledger.
  const rtSessions = withIdx(raw.rt_sessions);
  // What each plan has actually spent, counted the way the server counts it.
  const planUsage = withIdx(raw.plan_usage);
  // One row per (user, language) with the seconds spoken and which sources
  // know about it. `users[].langs` is still the plain code list.
  const userLangs = withIdx(raw.user_langs);
  // The onboarding CHOICE, only for rows a build has actually written.
  const setup = withIdx(raw.setup);
  // Talk seconds by UTC hour-of-day, per user. The page rotates them.
  const hours = withIdx(raw.hours);
  // One row per (user, UTC day, UTC hour): [user idx, "YYYY-MM-DD", hour,
  // talk seconds, server calls]. The page folds it into weekdays, weeks and
  // months — in the READER's zone, which is why the hour is still here and
  // why nothing is pre-bucketed by day. Absent on a Worker talking to a
  // database that has not had the day_hours migration yet, and the page
  // falls back to the launch-window cells.
  const dayHours = (raw.day_hours ?? [])
    .filter((r: any) => uidx.has(r.id))
    .map((r: any) => [uidx.get(r.id), r.d, r.h, r.secs, r.events, r.spoke ?? null]);
  // The last 8 days, one row per ledger row: [user idx, epoch ms, talk
  // seconds or -1 for a non-talk row]. Same seconds rule as
  // `talk_row_seconds`: metadata.seconds when present, else a negative delta.
  const recentActivity = (raw.recent_ledger ?? [])
    .filter((r: any) => uidx.has(r.user_id))
    .map((r: any) => [
      uidx.get(r.user_id),
      Date.parse(r.created_at),
      r.action !== "talk_time" ? -1
        : typeof r.seconds === "number" ? r.seconds
        : r.delta < 0 ? -r.delta : 0,
    ]);
  const rtReasons = raw.rt_reasons ?? [];

  // ---------------------------------------------------------------- truth
  // ElevenLabs' own numbers for the window, with the ledger beside them.
  // Everything metered in the window counts here, owner and test accounts
  // included: cost is cost.
  const talkMinWindow = cells.reduce((a: number, c: any) => a + c[4], 0) / 60;
  const scenesWindow = sceneCells.reduce((a: number, c: any) => a + c[2], 0);
  const gmUsdWindow = (raw.cost_daily ?? [])
    .filter((r: any) => dayIdx.has(r.d))
    .reduce((a: number, r: any) => a + (r.gm || 0), 0);
  const signupsWindow = raw.users.filter((u: any) => u.signed_up >= raw.windowStart && !u.anonymous).length;
  const econ = truth ? buildEcon(truth, {
    talkMin: talkMinWindow, scenes: scenesWindow, gmUsd: gmUsdWindow, days: days.length,
    signups: signupsWindow, commission: raw.commission, rateDb: raw.rate,
  }) : null;

  // ---------------------------------------------------------------- cost
  const m = raw.mech;
  const cpm = m.turn_chars / m.talk_min;
  const cps = m.scene_chars / m.plays;
  // With ElevenLabs' numbers in hand the talk figure is the REAL one (the
  // ledger's turn rows alone miss the gateway); the ledger's own mechanics
  // are the fallback.
  const talkC = econ && econ.unit.talkCreditsPerMin > 0
    ? econ.unit.talkCreditsPerMin : cpm * CREDITS_PER_CHAR.conversation;
  const sceneC = econ && econ.unit.sceneCredits > 0
    ? econ.unit.sceneCredits : cps * CREDITS_PER_CHAR.fidelity;
  // $/credit: the tier's list price when known, else what the database seeded.
  // The ledger's USD figures were priced at the database rate, so they are
  // rescaled below rather than re-summed.
  const rate = truth?.rate ?? raw.rate;
  const elScale = raw.rate ? rate / raw.rate : 1;
  const commission = raw.commission;

  const tiers = [];
  for (const p of raw.plans) {
    const price = MONTHLY_PRICE[p.id];
    if (price === undefined) continue;   // no price on record — don't guess one
    const mins = (p.monthly_seconds ?? 0) / 60;
    const scenes = p.monthly_scenes ?? 0;
    const net = price * (1 - commission);
    // Plus has no talk ceiling, so only the scene side can be bounded — its
    // monthly_seconds is descriptive and must not be spent as if enforced.
    const talkCredits = p.talk_unlimited ? 0 : mins * talkC;
    const sceneCredits = scenes * sceneC;
    const capped = talkCredits + sceneCredits;
    tiers.push({
      id: p.id, tier: p.tier, period: p.period,
      talk_unlimited: p.talk_unlimited,
      talk_min: p.talk_unlimited ? null : round(mins),
      scenes,
      talk_credits: round(talkCredits),
      scene_credits: round(sceneCredits),
      capped_credits: round(capped),
      scene_share: capped ? round((sceneCredits / capped) * 100) : null,
      price: round(price, 2), net: round(net, 2),
      capped_cost: round(capped * rate, 2),
      margin: round(net - capped * rate, 2),
      fill_breakeven_pct: capped ? round((net / (capped * rate)) * 100, 1) : null,
      scenes_breakeven: round(net / (sceneC * rate), 1),
      scenes_per_day_breakeven: round(net / (sceneC * rate) / 30, 1),
    });
  }

  // A user's ElevenLabs cost is TWO things (2026-09-26): what the ledger
  // priced (scenes, voicemail, shadowing, previews — and the app-side `turn`
  // rows), and the CALLS, which the gateway synthesizes without writing a
  // character anywhere. Until this the table was the ledger alone and summed
  // to 47% of ElevenLabs' meter over the launch window; a Plus subscriber
  // with 108 minutes of calls read $0.095. So talk is estimated from the
  // seconds the meter DID record, at the credits-per-minute measured from
  // ElevenLabs' usage API (`talkC`), and the ledger's turn rows are
  // subtracted first so a call on the old path isn't counted twice.
  // `raw.talk_cost` is optional (an un-applied migration) — without it the
  // table is the old ledger figure, and `talk_estimated` says so.
  const talkUsdPerMin = talkC * rate;
  const tcUser = new Map<string, any>();
  const tcMonth = new Map<string, any>();
  for (const r of raw.talk_cost?.user ?? []) tcUser.set(r.id, r);
  for (const r of raw.talk_cost?.month ?? []) tcMonth.set(`${r.month}|${r.id}`, r);
  const withTalk = (r: any, tc: any) => {
    if (!tc) return { el: round(r.el * elScale, 4), talk_el: null, talk_estimated: false };
    const ledgerEl = Math.max(0, r.el - (tc.turn_usd ?? 0)) * elScale;
    const talkEl = ((tc.talk_secs ?? 0) / 60) * talkUsdPerMin;
    return { el: round(ledgerEl + talkEl, 4), talk_el: round(talkEl, 4), talk_estimated: true };
  };

  const byUser: Record<string, any> = {};
  for (const r of raw.cost_user) if (uidx.has(r.id)) {
    const t = withTalk(r, tcUser.get(r.id));
    byUser[String(uidx.get(r.id))] = {
      ...r, ...t, usd: round(t.el + r.gm, 4),
      talk_secs: tcUser.get(r.id)?.talk_secs ?? null,
    };
  }

  const byUserMonth: Record<string, Record<string, any>> = {};
  for (const r of raw.cost_month) {
    if (!uidx.has(r.id)) continue;
    const t = withTalk(r, tcMonth.get(`${r.month}|${r.id}`));
    (byUserMonth[r.month] ??= {})[String(uidx.get(r.id))] = {
      usd: round(t.el + r.gm, 4), el: t.el, talk_el: t.talk_el, talk_estimated: t.talk_estimated,
      gm: r.gm, chars: r.chars, talk_secs: r.talk_secs, scenes: r.scenes,
    };
  }

  const cost = {
    talk_credits_per_min: round(talkC, 1),
    scene_credits: round(sceneC),
    ratio: round(sceneC / talkC, 1),
    chars_per_min: econ ? talkC / CREDITS_PER_CHAR.conversation : cpm,
    chars_per_scene: cps,
    usd_per_talk_min: round(talkC * rate, 4),
    usd_per_scene: round(sceneC * rate, 4),
    rate, commission,
    rateDb: raw.rate,
    // Where the unit figures come from: ElevenLabs' own usage over the launch
    // window, or the ledger's turn rows since the cost window.
    sample: econ
      ? { talk_min: round(talkMinWindow, 1), plays: Math.round(scenesWindow),
          since: raw.windowStart, source: "elevenlabs" }
      : { talk_min: round(m.talk_min, 1), plays: Math.round(m.plays),
          since: raw.cost_window, source: "ledger" },
    tiers,
    daily: raw.cost_daily
      .filter((r: any) => dayIdx.has(r.d))
      .map((r: any) => [dayIdx.get(r.d), round(r.el * elScale, 4), r.gm]),
    byUser,
    byUserMonth,
    talk_estimated: !!raw.talk_cost,
    months: Object.keys(byUserMonth).sort().reverse(),
    rates: raw.rates,
    unpriced: raw.unpriced,
    builds: raw.builds,
  };

  // ------------------------------------------------------------- revenue
  // Every price is monthly-equivalent (an annual plan divided by 12) so one
  // number can be added up. `comp` is excluded everywhere — a hand-given plan
  // is not revenue and never becomes any.
  const priceOf = (planId: string | null) =>
    planId ? (MONTHLY_PRICE[planId] ?? 0) : 0;
  const revenue = (() => {
    let paid = 0, trialLive = 0, trialLost = 0;
    let paidN = 0, trialLiveN = 0, trialLostN = 0, compN = 0;
    for (const u of users) {
      // The owner's own subscription is not revenue — it is the founder paying
      // himself to watch real burn. Counting it printed "결제 구독 0 · 월 $19.99"
      // on the same tile, which is the contradiction that gave it away.
      if (u.dev || u.owner) continue;
      const price = priceOf(u.plan);
      switch (u.subState) {
        case "paid":            paid += price; paidN++; break;
        case "cancelling":      paid += price; paidN++; break;
        case "trial":           trialLive += price; trialLiveN++; break;
        case "trial_cancelled": trialLost += price; trialLostN++; break;
        case "comp":            compN++; break;
      }
    }
    const trials = trialLiveN + trialLostN;
    return {
      mrr: round(paid, 2), mrrCount: paidN,
      trialLive: round(trialLive, 2), trialLiveCount: trialLiveN,
      trialLost: round(trialLost, 2), trialLostCount: trialLostN,
      compCount: compN,
      trials,
      // Of the trials that have been STARTED, how many still intend to bill.
      keepRate: trials ? round((trialLiveN / trials) * 100) : null,
      commission: raw.commission,
      // What lands in the bank if every running trial converts.
      netIfAllConvert: round((paid + trialLive) * (1 - raw.commission), 2),
    };
  })();

  return {
    asOf: raw.today,
    liveAt: raw.liveAt,
    windowStart: raw.windowStart,
    days, users, cells, sceneCells, sessions, errorsDaily,
    features: raw.features,
    waitlist: {
      total: raw.waitlist.total,
      wantsBeta: raw.waitlist.wants_beta,
      converted: raw.waitlist.converted,
      channels: raw.channels,
    },
    cost,
    econ,
    fairUse: raw.fair_use,
    subEvents, recentSessions, recentEvents, freeRecent,
    rtSessions, rtReasons, revenue, planUsage, userLangs, setup, hours, recentActivity,
    dayHours,
    prices: MONTHLY_PRICE,
    storePrices: STORE_PRICES,
  };
}
