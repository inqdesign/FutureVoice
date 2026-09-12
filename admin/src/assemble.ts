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
const TEST_IDS = new Set(["ecd78251-49c4-4e18-a156-6fbe90fd6e3b"]);

// Apple's cut and the sticker prices. Prices live in docs/launch-billing.md;
// they are NOT in the database (there is no price column), so they are stated
// here and nowhere else in this pipeline.
const MONTHLY_PRICE: Record<string, number> = {
  light_monthly: 9.99,
  light_annual: 79.99 / 12,
  plus_monthly: 19.99,
  plus_annual: 143.99 / 12,
};
// Credits per character come from the model, not the plan: multilingual_v2
// (the fidelity model, used by Watch scenes and the onboarding greeting) bills
// 1.0 credit/char, turbo and flash bill 0.5.
const CREDITS_PER_CHAR = { fidelity: 1.0, conversation: 0.5 };

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

const deviceOf = (ua: string | null) =>
  !ua ? null : ua.includes("iPhone") ? "iPhone" : ua.includes("iPad") ? "iPad" : null;

export function assemble(raw: any) {
  const days = daysBetween(raw.windowStart, raw.today);
  const dayIdx = new Map<string, number>(days.map((d, i) => [d, i]));
  const uidx = new Map<string, number>(raw.users.map((u: any, i: number) => [u.id, i]));

  const idx = (r: any) => uidx.get(r.id);
  const keep = (r: any) => uidx.has(r.id) && dayIdx.has(r.d);

  const cells = raw.cells.filter(keep).map((r: any) =>
    [idx(r), dayIdx.get(r.d), r.rows, r.turns, r.secs]);
  const sceneCells = raw.scenes.filter(keep).map((r: any) =>
    [idx(r), dayIdx.get(r.d), r.n]);
  const sessions = raw.sessions.filter(keep).map((r: any) =>
    [idx(r), dayIdx.get(r.d), r.secs]);
  const errorsDaily = raw.errors
    .filter((r: any) => dayIdx.has(r.d))
    .map((r: any) => [dayIdx.get(r.d), r.n]);

  // ---------------------------------------------------------------- users
  const agg = new Map<number, { days: Set<number>; turns: number; secs: number }>();
  for (const c of cells) {
    const a = agg.get(c[0]) ?? { days: new Set<number>(), turns: 0, secs: 0 };
    a.days.add(c[1]); a.turns += c[3]; a.secs += c[4];
    agg.set(c[0], a);
  }
  const sceneTot = new Map<number, number>();
  for (const s of sceneCells) sceneTot.set(s[0], (sceneTot.get(s[0]) ?? 0) + s[2]);
  const sessCt = new Map<number, number>();
  for (const s of sessions) sessCt.set(s[0], (sessCt.get(s[0]) ?? 0) + 1);

  const langByUser = new Map<string, string[]>(
    raw.langs.map((l: any) => [l.id, l.langs]));

  const users = raw.users.map((u: any, i: number) => {
    const a = agg.get(i) ?? { days: new Set<number>(), turns: 0, secs: 0 };
    const ds = [...a.days].sort((x, y) => x - y);
    const rv = raw.reviews
      .filter((r: any) => r.id === u.id)
      .map((r: any) => ({ context: r.context, rating: r.rating, body: r.body, d: r.d }));
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
      signedUp: u.signed_up,
      origin: preWindow ? raw.windowStart : u.signed_up,
      preWindow,
      plan: u.plan_id, subStatus: u.sub_status, trialEnds: u.trial_ends,
      balance: u.balance, clone: u.clone,
      activeDays: ds.length,
      firstActive: ds.length ? days[ds[0]] : null,
      lastActive: ds.length ? days[ds[ds.length - 1]] : null,
      turns: a.turns, talkSecs: a.secs,
      talkSessions: sessCt.get(i) ?? 0, scenes: sceneTot.get(i) ?? 0,
      reviewCount: rv.length, langs: langByUser.get(u.id) ?? [],
      name: u.display_name, realEmail: u.real_email,
      occupation: u.occupation, location: u.location,
      interests: u.interests, intro: u.intro,
      channel: u.channel, device: deviceOf(u.user_agent),
      waitlistAt: u.waitlist_at, reviews: rv,
    };
  });

  // ---------------------------------------------------------------- cost
  const m = raw.mech;
  const cpm = m.turn_chars / m.talk_min;
  const cps = m.scene_chars / m.plays;
  const talkC = cpm * CREDITS_PER_CHAR.conversation;
  const sceneC = cps * CREDITS_PER_CHAR.fidelity;
  const rate = raw.rate;
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

  const byUser: Record<string, any> = {};
  for (const r of raw.cost_user) if (uidx.has(r.id)) byUser[String(uidx.get(r.id))] = r;

  const byUserMonth: Record<string, Record<string, any>> = {};
  for (const r of raw.cost_month) {
    if (!uidx.has(r.id)) continue;
    (byUserMonth[r.month] ??= {})[String(uidx.get(r.id))] = {
      usd: r.usd, el: r.el, gm: r.gm, chars: r.chars,
      talk_secs: r.talk_secs, scenes: r.scenes,
    };
  }

  const cost = {
    talk_credits_per_min: round(talkC, 1),
    scene_credits: round(sceneC),
    ratio: round(sceneC / talkC, 1),
    chars_per_min: cpm,
    chars_per_scene: cps,
    usd_per_talk_min: round(talkC * rate, 4),
    usd_per_scene: round(sceneC * rate, 4),
    rate, commission,
    sample: { talk_min: round(m.talk_min, 1), plays: Math.round(m.plays),
              since: raw.cost_window },
    tiers,
    daily: raw.cost_daily
      .filter((r: any) => dayIdx.has(r.d))
      .map((r: any) => [dayIdx.get(r.d), r.el, r.gm]),
    byUser,
    byUserMonth,
    months: Object.keys(byUserMonth).sort().reverse(),
    rates: raw.rates,
    unpriced: raw.unpriced,
    builds: raw.builds,
  };

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
    fairUse: raw.fair_use,
  };
}
