"""Derive the unit economics the admin console's 비용 tab is built from.

Two measured quantities decide everything here:

  * chars of conversation TTS per minute of metered talk
  * chars of scene TTS per scene actually played

Both are read over a window that starts when scene counting shipped
(2026-08-14) — before that `scene_plays` was not written, so any earlier
window silently inflates the per-scene figure by counting scene audio whose
plays were never recorded.

Credits per character come from the model, not the plan: multilingual_v2
(the fidelity model, used by Watch scenes and the onboarding greeting) bills
1.0 credit/char, turbo and flash bill 0.5. That 2x, multiplied by scenes
being pure synthesized speech while half a talk minute is the learner's own
voice, is the whole reason a scene costs several talk minutes.

Writes derived.json into $ADMIN_OUT (default ./build), which gather_admin.py
then folds into the page's data blob.
"""
import os, sys, json, pathlib

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
OUT = pathlib.Path(os.environ.get("ADMIN_OUT", HERE / "build"))
OUT.mkdir(parents=True, exist_ok=True)
from pq import run

WINDOW_START = "2026-08-14"   # scene_plays begins here

# Apple's cut and the sticker prices. Prices live in docs/launch-billing.md;
# they are NOT in the database (there is no price column), so they are stated
# here and nowhere else in this pipeline.
MONTHLY_PRICE = {
    "light_monthly": 9.99,
    "light_annual":  79.99 / 12,
    "plus_monthly":  19.99,
    "plus_annual":   143.99 / 12,
}
CREDITS_PER_CHAR = {"fidelity": 1.0, "conversation": 0.5}


def q(sql, label):
    r = run(sql)
    if isinstance(r, dict):
        print(f"!! {label}: {r}", file=sys.stderr)
        sys.exit(1)
    return r


mech = q(f"""
with w as (select date '{WINDOW_START}' as d0),
tm as (select sum(public.talk_row_seconds(metadata, delta))/60.0 as m
       from public.usage_ledger, w
       where action = 'talk_time' and created_at >= d0),
tc as (select sum((metadata->>'chars')::numeric) as c
       from public.usage_ledger, w
       where action = 'tts' and metadata->>'purpose' = 'turn' and created_at >= d0),
sc as (select sum((metadata->>'chars')::numeric) as c
       from public.usage_ledger, w
       where metadata->>'purpose' = 'scene' and created_at >= d0),
sp as (select count(*)::numeric as n from public.scene_plays, w where created_at >= d0)
select tm.m::float8 as talk_min, tc.c::float8 as turn_chars,
       (tc.c/nullif(tm.m,0))::float8 as chars_per_min,
       sp.n::float8 as plays, sc.c::float8 as scene_chars,
       (sc.c/nullif(sp.n,0))::float8 as chars_per_scene
from tm, tc, sc, sp
""", "mechanism")[0]

rate = q("""
select usd_per_unit::float8 as r from public.provider_rates
where provider='elevenlabs' and model='eleven_turbo_v2_5' and unit='char'
order by effective_from desc limit 1
""", "rate")[0]["r"] / CREDITS_PER_CHAR["conversation"]   # back to $/credit

commission = q("""
select usd_per_unit::float8 as c from public.provider_rates
where provider='apple' and unit='commission_fraction'
order by effective_from desc limit 1
""", "commission")[0]["c"]

plans = q("""
select id, tier, period, monthly_seconds, monthly_scenes, talk_unlimited
from public.subscription_plans where is_active order by tier, period
""", "plans")

cpm = mech["chars_per_min"]
cps = mech["chars_per_scene"]
talk_c = cpm * CREDITS_PER_CHAR["conversation"]
scene_c = cps * CREDITS_PER_CHAR["fidelity"]

out = {
    "talk_credits_per_min": round(talk_c, 1),
    "scene_credits": round(scene_c),
    "ratio": round(scene_c / talk_c, 1),
    "chars_per_min": cpm,
    "chars_per_scene": cps,
    "usd_per_talk_min": round(talk_c * rate, 4),
    "usd_per_scene": round(scene_c * rate, 4),
    "rate": rate,
    "commission": commission,
    "sample": {"talk_min": round(mech["talk_min"], 1),
               "plays": int(mech["plays"]), "since": WINDOW_START},
    "tiers": [],
}

for p in plans:
    mins = (p["monthly_seconds"] or 0) / 60.0
    scenes = p["monthly_scenes"] or 0
    price = MONTHLY_PRICE.get(p["id"])
    if price is None:
        print(f"   (skipping {p['id']}: no price on record)", file=sys.stderr)
        continue
    net = price * (1 - commission)
    # Plus has no talk ceiling, so only the scene side can be bounded — its
    # monthly_seconds is descriptive and must not be spent as if enforced.
    talk_credits = 0 if p["talk_unlimited"] else mins * talk_c
    scene_credits = scenes * scene_c
    capped = talk_credits + scene_credits
    out["tiers"].append({
        "id": p["id"], "tier": p["tier"], "period": p["period"],
        "talk_unlimited": p["talk_unlimited"],
        "talk_min": None if p["talk_unlimited"] else round(mins),
        "scenes": scenes,
        "talk_credits": round(talk_credits),
        "scene_credits": round(scene_credits),
        "capped_credits": round(capped),
        "scene_share": round(scene_credits / capped * 100) if capped else None,
        "price": round(price, 2), "net": round(net, 2),
        "capped_cost": round(capped * rate, 2),
        "margin": round(net - capped * rate, 2),
        "fill_breakeven_pct": round(net / (capped * rate) * 100, 1) if capped else None,
        "scenes_breakeven": round(net / (scene_c * rate), 1),
        "scenes_per_day_breakeven": round(net / (scene_c * rate) / 30, 1),
    })

json.dump(out, open(OUT / "derived.json", "w"), indent=1)
print(f"1 scene = {out['ratio']} talk minutes | "
      f"${out['usd_per_talk_min']}/min, ${out['usd_per_scene']}/scene "
      f"@ ${rate:.8f}/credit", file=sys.stderr)
for t in out["tiers"]:
    tl = "no ceiling" if t["talk_unlimited"] else f"{t['talk_min']} min"
    print(f"  {t['id']:15} talk={tl:>10} scenes={t['scenes']:>3}  "
          f"capped=${t['capped_cost']:>7}  net=${t['net']:>5}  "
          f"break-even at {t['fill_breakeven_pct']}%", file=sys.stderr)
