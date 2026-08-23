"""Rebuild the admin console's data blob from production.

Produces the SAME shape the existing 유저 활동 dashboard uses (so none of its
charts have to change), plus a `cost` key for the new margin tab.
"""
import sys, json, datetime
import os, pathlib
HERE = pathlib.Path(__file__).resolve().parent
OUT = pathlib.Path(os.environ.get("ADMIN_OUT", HERE / "build")); OUT.mkdir(parents=True, exist_ok=True)

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pq import run

# The owner is a REAL user of the product, not a test fixture — he practises
# on it daily, and his account is the only one with enough metered talk to
# derive a cost per minute from. So he is included everywhere by default and
# merely marked. Only the synthetic device-test account is filtered, and that
# one is genuinely not a person.
# Everything on this page starts the day Talk became the unit of account.
# 2026-08-10 is where the first `talk_time`, the first `tts_scene` and the
# first `free_usage_daily` rows all appear — before it there is no metered
# talk, no scene count and no per-purpose usage, so any earlier day can only
# be compared on turn counts and silently drags every average down.
WINDOW_START = "2026-08-10"

OWNER_ID = "72bcaa7e-3dd2-4364-b197-078ba59c1ce4"
TEST_IDS = {"ecd78251-49c4-4e18-a156-6fbe90fd6e3b"}

def q(sql, label):
    r = run(sql.replace("{W}", WINDOW_START))
    if isinstance(r, dict):
        print(f"!! {label}: {r}", file=sys.stderr); sys.exit(1)
    print(f"   {label}: {len(r)} rows", file=sys.stderr)
    return r

# ---------------------------------------------------------------- users
users_raw = q("""
select u.id::text as id,
       u.email,
       u.created_at::date::text                     as signed_up,
       s.plan_id, s.status as sub_status,
       s.trial_ends_at::date::text                  as trial_ends,
       c.balance,
       (vc.id is not null)                          as clone,
       p.display_name, p.occupation, p.location, p.interests, p.intro,
       w.email                                      as real_email,
       w.referrer                                   as channel,
       w.user_agent,
       w.created_at::date::text                     as waitlist_at
from auth.users u
left join public.user_subscriptions s on s.user_id = u.id
left join public.user_credits c       on c.user_id = u.id
left join lateral (select id from public.voice_clones v
                    where v.user_id = u.id limit 1) vc on true
left join lateral (select pp.display_name, pp.occupation, pp.location,
                          pp.interests, pp.intro
                     from public.public_personas pp
                    where pp.owner_user_id = u.id and pp.is_active
                    order by pp.updated_at desc limit 1) p on true
left join lateral (select wl.email, wl.referrer, wl.user_agent, wl.created_at
                     from public.user_waitlist_mapping m
                     join public.waitlist wl on wl.email = m.waitlist_email
                    where m.user_id = u.id limit 1) w on true
order by u.created_at
""", "users")

# languages actually practised, from the Core's per-language ledger
langs = q("""
select user_id::text as id, array_agg(distinct language order by language) as langs
from public.talk_seconds_by_language group by 1
""", "langs")
lang_by_user = {r["id"]: r["langs"] for r in langs}

reviews = q("""
select user_id::text as id, context, rating, body, created_at::date::text as d
from public.beta_reviews order by created_at
""", "reviews")

# ---------------------------------------------------------------- day axis
d0 = datetime.date.fromisoformat(WINDOW_START)
today = datetime.date.fromisoformat(q("select current_date::text as d", "today")[0]["d"])
days = [(d0 + datetime.timedelta(days=i)).isoformat()
        for i in range((today - d0).days + 1)]
day_idx = {d: i for i, d in enumerate(days)}

order = [u["id"] for u in users_raw]
uidx = {uid: i for i, uid in enumerate(order)}

# ---------------------------------------------------------------- daily cells
cells_raw = q("""
select user_id::text as id, created_at::date::text as d,
       count(*)                                              as rows,
       -- One conversation turn = one reply call. NOT every Gemini call: a
       -- turn also fires a transcribe call, and TTS splits a reply into two
       -- requests, so counting those double- or triple-counts the turn.
       -- Speculative replies carry purpose='turn' too but are frequently
       -- thrown away, so a tagged one is excluded; rows written before the
       -- tag existed have no `spec` key and still count, which is correct.
       count(*) filter (where source_fn='gemini'
                          and metadata->>'purpose'='turn'
                          and coalesce(metadata->>'spec','false') <> 'true')
                                                             as turns,
       coalesce(sum(public.talk_row_seconds(metadata, delta))
                filter (where action='talk_time'), 0)::int    as secs
from public.usage_ledger
where created_at >= date '{W}'
group by 1,2
""", "cells")
cells = [[uidx[r["id"]], day_idx[r["d"]], r["rows"], r["turns"], r["secs"]]
         for r in cells_raw if r["id"] in uidx and r["d"] in day_idx]

scene_raw = q("""
select user_id::text as id, day::text as d, count(*) as n
from public.scene_plays where created_at >= date '{W}' group by 1,2
""", "scenes")
scene_cells = [[uidx[r["id"]], day_idx[r["d"]], r["n"]]
               for r in scene_raw if r["id"] in uidx and r["d"] in day_idx]

# ---------------------------------------------------------------- sessions
sessions_raw = q("""
select user_id::text as id, min(created_at)::date::text as d,
       sum(public.talk_row_seconds(metadata, delta))::int as secs
from public.usage_ledger
where action='talk_time' and metadata->>'session_id' is not null
  and created_at >= date '{W}'
group by user_id, metadata->>'session_id'
""", "sessions")
sessions = [[uidx[r["id"]], day_idx[r["d"]], r["secs"]]
            for r in sessions_raw if r["id"] in uidx and r["d"] in day_idx]

errors_raw = q("""
select created_at::date::text as d, count(*) as n
from public.client_events
where (event ilike '%error%' or event ilike '%fail%')
  and created_at >= date '{W}'
group by 1 order by 1
""", "errors")
errors_daily = [[day_idx[r["d"]], r["n"]] for r in errors_raw if r["d"] in day_idx]

features = q("""
select purpose, sum("count")::int as total, count(distinct user_id) as users
from public.free_usage_daily where day >= date '{W}' group by 1 order by 2 desc
""", "features")

# ---------------------------------------------------------------- builds seen
builds = q("""
select coalesce(properties->>'build','(unknown)') as build,
       count(distinct user_id) as users, max(created_at)::date::text as last_seen
from public.client_events
where created_at >= current_date - 30
group by 1 order by 3 desc, 2 desc
""", "builds")

# ---------------------------------------------------------------- waitlist
wl = q("""
select count(*) as total,
       count(*) filter (where wants_beta) as wants_beta,
       (select count(*) from public.user_waitlist_mapping) as converted
from public.waitlist
""", "waitlist")[0]
channels = q("""
select coalesce(referrer,'(없음)') as name, count(*) as n,
       count(*) filter (where wants_beta) as beta
from public.waitlist group by 1 order by 2 desc
""", "channels")

# ---------------------------------------------------------------- assemble users
agg = {}
for c in cells:
    a = agg.setdefault(c[0], {"days": set(), "turns": 0, "secs": 0})
    a["days"].add(c[1]); a["turns"] += c[3]; a["secs"] += c[4]
scene_tot = {}
for s in scene_cells:
    scene_tot[s[0]] = scene_tot.get(s[0], 0) + s[2]
sess_ct = {}
for s in sessions:
    sess_ct[s[0]] = sess_ct.get(s[0], 0) + 1

def device_of(ua):
    if not ua: return None
    return "iPhone" if "iPhone" in ua else ("iPad" if "iPad" in ua else None)

users = []
for i, u in enumerate(users_raw):
    a = agg.get(i, {"days": set(), "turns": 0, "secs": 0})
    dev = u["id"] in TEST_IDS
    owner = u["id"] == OWNER_ID
    name = u["display_name"]
    label = name or (u["email"].split("@")[0] if u["email"] else u["id"][:8])
    rv = [{"context": r["context"], "rating": r["rating"], "body": r["body"], "d": r["d"]}
          for r in reviews if r["id"] == u["id"]]
    ds = sorted(a["days"])
    # Someone who signed up before the cutover is only observed from it, so
    # streaks and week-N retention must be counted from there — not from a
    # signup date whose first weeks this page cannot see.
    pre_window = u["signed_up"] < WINDOW_START
    origin = WINDOW_START if pre_window else u["signed_up"]
    users.append({
        "id": u["id"], "label": label, "email": u["email"],
        "dev": dev, "owner": owner,
        "signedUp": u["signed_up"], "origin": origin, "preWindow": pre_window,
        "plan": u["plan_id"], "subStatus": u["sub_status"],
        "trialEnds": u["trial_ends"], "balance": u["balance"], "clone": u["clone"],
        "activeDays": len(ds),
        "firstActive": days[ds[0]] if ds else None,
        "lastActive": days[ds[-1]] if ds else None,
        "turns": a["turns"], "talkSecs": a["secs"],
        "talkSessions": sess_ct.get(i, 0), "scenes": scene_tot.get(i, 0),
        "reviewCount": len(rv), "langs": lang_by_user.get(u["id"], []),
        "name": name, "realEmail": u["real_email"],
        "occupation": u["occupation"], "location": u["location"],
        "interests": u["interests"], "intro": u["intro"],
        "channel": u["channel"], "device": device_of(u["user_agent"]),
        "waitlistAt": u["waitlist_at"], "reviews": rv,
    })

# ---------------------------------------------------------------- cost
cost = json.load(open(OUT / "derived.json"))
cost_daily = q("""
select day::text as d,
       round(sum(elevenlabs_usd)::numeric,4)::float8 as el,
       round(sum(gemini_usd)::numeric,4)::float8     as gm
from public.user_daily_usage where day >= date '{W}' group by 1 order by 1
""", "cost_daily")
cost_user = q("""
select user_id::text as id,
       round(sum(total_usd)::numeric,4)::float8      as usd,
       round(sum(elevenlabs_usd)::numeric,4)::float8 as el,
       round(sum(gemini_usd)::numeric,4)::float8     as gm,
       round(sum(tts_chars)::numeric)::float8        as chars,
       bool_or(has_unpriced)                         as unpriced
from public.user_daily_usage where day >= date '{W}' group by 1
""", "cost_user")
cost["daily"] = [[day_idx[r["d"]], r["el"], r["gm"]] for r in cost_daily if r["d"] in day_idx]
cost["byUser"] = {str(uidx[r["id"]]): r for r in cost_user if r["id"] in uidx}

# Same figures cut by calendar month, so the table can be read a month at a
# time. Talk and scenes ride along: a cost column filtered to August beside a
# talk column counting everything would invite exactly the wrong comparison.
cost_month = q("""
select to_char(day,'YYYY-MM')                       as month,
       user_id::text                                as id,
       round(sum(total_usd)::numeric,4)::float8     as usd,
       round(sum(elevenlabs_usd)::numeric,4)::float8 as el,
       round(sum(gemini_usd)::numeric,4)::float8    as gm,
       round(sum(tts_chars)::numeric)::float8       as chars,
       sum(talk_seconds)::int                       as talk_secs,
       sum(scenes)::int                             as scenes
from public.user_daily_usage
where day >= date '{W}'
group by 1,2
""", "cost_month")
by_month = {}
for r in cost_month:
    if r["id"] not in uidx:
        continue
    by_month.setdefault(r["month"], {})[str(uidx[r["id"]])] = {
        k: r[k] for k in ("usd", "el", "gm", "chars", "talk_secs", "scenes")}
cost["byUserMonth"] = by_month
cost["months"] = sorted(by_month.keys(), reverse=True)
cost["rates"] = q("""
select provider, model, unit, usd_per_unit::float8 as usd,
       effective_from::date::text as since, note
from public.provider_rates order by provider, model, unit
""", "rates")
cost["unpriced"] = q("""
select provider, model, unit, rows::int, units::float8 from public.unpriced_usage
""", "unpriced")
cost["builds"] = builds

DATA = {
    "asOf": today.isoformat(),
    "windowStart": WINDOW_START,
    "days": days,
    "users": users,
    "cells": cells,
    "sceneCells": scene_cells,
    "sessions": sessions,
    "errorsDaily": errors_daily,
    "features": features,
    "waitlist": {"total": wl["total"], "wantsBeta": wl["wants_beta"],
                 "converted": wl["converted"], "channels": channels},
    "cost": cost,
}
out = str(OUT / "admin_data.json")
json.dump(DATA, open(out, "w"), separators=(",", ":"), default=str)
print(f"\nwrote {out} ({len(open(out).read())} bytes)", file=sys.stderr)
print(f"users={len(users)} days={len(days)} cells={len(cells)} "
      f"sessions={len(sessions)} costDaily={len(cost['daily'])}", file=sys.stderr)
