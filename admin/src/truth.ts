// What ElevenLabs actually billed, read from ElevenLabs — not from the ledger.
//
// The ledger (`usage_ledger`) sees under half of the real credits: the
// realtime gateway, which is the main Talk path, streams to ElevenLabs
// directly and records seconds for the meter but never a character count
// (gateway/src/billing.ts). Accent previews (text-to-voice) record a row with
// no credits at all. Found 2026-09-24: 217k credits on the ElevenLabs
// dashboard for the launch cycle against 104k in the ledger — and the
// ledger's own per-credit rate was still the Creator seed ($0.00022) while
// the account is on Pro ($99 / 600k = $0.000165), so two errors of opposite
// sign were hiding each other. Everything under 실제 원가 on the 돈 tab reads
// from here, and the tier/unit figures in assemble.ts take this rate when
// the key is set.
//
// Two ElevenLabs calls per page load, held 5 min per isolate (the API is
// rate-limited per key and a reload does not change last hour's usage):
//   GET /v1/user/subscription            — tier, used, limit, reset
//   GET /v1/usage/character-stats        — credits per day per model
// plus one paged REST read of the ledger's TTS rows in the same window, so
// the page can say which credits the ledger knows about and which it doesn't.

export type TruthModelDay = Record<string, number>;   // model → credits

export interface Truth {
  fetchedAt: string;
  tier: string;
  /** Credits used / included in the CURRENT ElevenLabs cycle, and when it resets. */
  cycle: { used: number; limit: number; resetAt: string | null; startedAt: string | null };
  /** USD per credit for the tier the account is on, from the public price list. */
  rate: number;
  tierPrice: number;
  tierCredits: number;
  windowStart: string;
  /** Credits per model, per day, from windowStart (ElevenLabs' own numbers). */
  days: { d: string; models: TruthModelDay }[];
  /** Same, summed over the window. */
  models: TruthModelDay;
  /** What the ledger recorded in the same window: credits by purpose+model,
   *  and per day. Absent when the REST read failed. */
  ledger: {
    byPurpose: Record<string, { credits: number; rows: number; model: string }>;
    byDay: Record<string, number>;
    total: number;
  } | null;
  fx: { USD: number; KRW: number; asOf: string; source: "frankfurter" | "fallback" };
  /** Custom-voice capacity on the account (same subscription call). Every
   *  learner's clone takes one slot out of `limit` for the WHOLE account, and
   *  each (re)clone or remix spends one of the month's add/edits. null fields
   *  = the response didn't carry them. */
  voices: { used: number | null; limit: number | null; addEdits: number | null; maxAddEdits: number | null };
  error?: string;
}

// The public price list (elevenlabs.io/pricing, read 2026-09-24). Per-credit
// cost is flat across Pro/Scale/Business — a tier buys capacity, not a lower
// rate — which is why the model page does not treat the tier as a lever.
const TIERS: Record<string, { price: number; credits: number }> = {
  free:     { price: 0,   credits: 10_000 },
  starter:  { price: 6,   credits: 30_000 },
  creator:  { price: 22,  credits: 121_000 },
  pro:      { price: 99,  credits: 600_000 },
  scale:    { price: 299, credits: 1_800_000 },
  business: { price: 990, credits: 6_000_000 },
};
export const TIER_LIST = Object.entries(TIERS)
  .filter(([k]) => k !== "free")
  .map(([name, t]) => ({ name, ...t }));

const CREDITS_PER_CHAR: Record<string, number> = {
  eleven_multilingual_v2: 1.0,
  eleven_turbo_v2_5: 0.5,
  eleven_flash_v2_5: 0.5,
  eleven_v3: 1.0,
};

const HOLD_MS = 5 * 60_000;
let held: { at: number; key: string; value: Truth } | null = null;

// EUR base. Refreshed twice a day; the fallback is the 2026-09-23 ECB fix so a
// blocked fetch degrades to a rate a few percent stale, never to no page.
const FX_FALLBACK = { USD: 1.1411, KRW: 1558.0, asOf: "2026-09-23" };
let fxHeld: { at: number; value: Truth["fx"] } | null = null;
async function fx(): Promise<Truth["fx"]> {
  if (fxHeld && Date.now() - fxHeld.at < 12 * 3_600_000) return fxHeld.value;
  try {
    const r = await fetch("https://api.frankfurter.dev/v1/latest?base=EUR&symbols=USD,KRW");
    if (!r.ok) throw new Error(`frankfurter ${r.status}`);
    const j = await r.json() as { date: string; rates: { USD: number; KRW: number } };
    fxHeld = { at: Date.now(), value: { USD: j.rates.USD, KRW: j.rates.KRW, asOf: j.date, source: "frankfurter" } };
  } catch {
    fxHeld = { at: Date.now(), value: { ...FX_FALLBACK, source: "fallback" } };
  }
  return fxHeld.value;
}

function numOrNull(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

async function eleven(path: string, key: string): Promise<any> {
  const r = await fetch(`https://api.elevenlabs.io${path}`, { headers: { "xi-api-key": key } });
  if (!r.ok) throw new Error(`elevenlabs ${path.split("?")[0]} ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return r.json();
}

/** The ledger's TTS rows in the window: one thin row per synthesis, paged. */
async function ledgerTts(env: { SUPABASE_URL: string; SUPABASE_SERVICE_ROLE_KEY: string }, since: string) {
  const page = 1000;
  const byPurpose: Record<string, { credits: number; rows: number; model: string }> = {};
  const byDay: Record<string, number> = {};
  let total = 0;
  for (let from = 0; from < 60_000; from += page) {
    const url = `${env.SUPABASE_URL}/rest/v1/usage_ledger`
      + `?select=created_at,action,purpose:metadata->>purpose,model:metadata->>model_id,chars:metadata->chars`
      + `&action=in.(tts,tts_scene,tts_timestamps)`
      + `&created_at=gte.${encodeURIComponent(since + "T00:00:00Z")}&order=created_at.asc`;
    const r = await fetch(url, {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        Range: `${from}-${from + page - 1}`,
      },
    });
    if (!r.ok) throw new Error(`usage_ledger tts ${r.status}: ${(await r.text()).slice(0, 200)}`);
    const batch = await r.json() as { created_at: string; action: string; purpose: string | null; model: string | null; chars: unknown }[];
    for (const x of batch) {
      const chars = typeof x.chars === "number" ? x.chars : 0;
      if (!chars) continue;
      // Rows older than 2026-08-23 carry no model_id; the same back-fill rule
      // as usage_cost_component (scene/greeting are the fidelity model).
      const model = x.model ?? (["scene", "greeting", "voice_comparison"].includes(x.purpose ?? "")
        ? "eleven_multilingual_v2" : "eleven_turbo_v2_5");
      const credits = chars * (CREDITS_PER_CHAR[model] ?? 1.0);
      const key = `${x.purpose ?? "unknown"}|${model}`;
      const p = byPurpose[key] ??= { credits: 0, rows: 0, model };
      p.credits += credits; p.rows++;
      const d = x.created_at.slice(0, 10);
      byDay[d] = (byDay[d] ?? 0) + credits;
      total += credits;
    }
    if (batch.length < page) break;
  }
  return { byPurpose, byDay, total };
}

export async function elevenTruth(
  env: { ELEVENLABS_API_KEY?: string; SUPABASE_URL: string; SUPABASE_SERVICE_ROLE_KEY: string },
  windowStart: string,
): Promise<Truth | null> {
  const key = env.ELEVENLABS_API_KEY;
  if (!key) return null;
  if (held && held.key === windowStart && Date.now() - held.at < HOLD_MS) return held.value;

  const startMs = Date.parse(windowStart + "T00:00:00Z");
  const endMs = Date.now();
  const [sub, stats, rates, ledger] = await Promise.all([
    eleven("/v1/user/subscription", key),
    eleven(`/v1/usage/character-stats?start_unix=${startMs}&end_unix=${endMs}&breakdown_type=model&aggregation_interval=day`, key),
    fx(),
    ledgerTts(env, windowStart).catch((e) => { console.log(`ledgerTts: ${(e as Error).message}`); return null; }),
  ]);

  const tier = String(sub.tier ?? "unknown").toLowerCase();
  const t = TIERS[tier] ?? TIERS.pro;
  const days: Truth["days"] = [];
  const models: TruthModelDay = {};
  const times: number[] = stats.time ?? [];
  const usage: Record<string, number[]> = stats.usage ?? {};
  times.forEach((ms, i) => {
    const d = new Date(ms).toISOString().slice(0, 10);
    const row: TruthModelDay = {};
    for (const [model, arr] of Object.entries(usage)) {
      const v = Number(arr[i] ?? 0);
      if (!v) continue;
      row[model] = v;
      models[model] = (models[model] ?? 0) + v;
    }
    if (Object.keys(row).length) days.push({ d, models: row });
  });

  const resetUnix = Number(sub.next_character_count_reset_unix ?? 0);
  const value: Truth = {
    fetchedAt: new Date().toISOString(),
    tier,
    cycle: {
      used: Number(sub.character_count ?? 0),
      limit: Number(sub.character_limit ?? t.credits),
      resetAt: resetUnix ? new Date(resetUnix * 1000).toISOString() : null,
      // Monthly cycle: the reset a month before the next one.
      startedAt: resetUnix ? new Date(new Date(resetUnix * 1000).setUTCMonth(new Date(resetUnix * 1000).getUTCMonth() - 1)).toISOString() : null,
    },
    rate: t.credits ? t.price / t.credits : 0,
    tierPrice: t.price,
    tierCredits: t.credits,
    windowStart,
    days, models, ledger, fx: rates,
    voices: {
      used: numOrNull(sub.voice_slots_used),
      limit: numOrNull(sub.voice_limit),
      addEdits: numOrNull(sub.voice_add_edit_counter),
      maxAddEdits: numOrNull(sub.max_voice_add_edits),
    },
  };
  held = { at: Date.now(), key: windowStart, value };
  return value;
}
