#!/usr/bin/env python3
"""The marketing team's only door to its tables (marketing/AUTOMATION.md §3).

Production, via the Supabase Management API with the Supabase CLI's keychain
token — the same path scripts/community.py uses. The tables are RLS-locked
with no policies, so nothing else can write them.

    db.py piece-upsert <slug> [--version V --build N --phase P --title-ko … --title-en … --one-message …]
    db.py stage <slug> <stage> [--note "…"]
    db.py set <slug> key=value …               # review_verdict, captions, slides (JSON), error …
    db.py event <slug|-> <kind> "<message>"    # '-' = a run-level event with no piece
    db.py schedule <slug> [--hours 12]         # stage=scheduled, scheduled_at=now()+hours
    db.py list [--stage S] [--version V] [--json]
    db.py get <slug>                           # one piece as JSON
    db.py slides-merge <slug> '<json array>'   # merge by n, keeps alt_ko/alt_en (media.sh --set-slides)
    db.py metrics-add <slug> <channel> views=… likes=… …

`set` takes the literal value `null` to clear a column. `slides` must be a JSON
array; `build`/`review_fixes` integers; `show_in_community` true/false;
timestamps ISO-8601 or `now`.

scheduler.py and metrics.py import this module (sql, lit, load_env, …).
"""
import argparse, base64, json, os, re, secrets, subprocess, sys, urllib.error, urllib.request

PROJECT = "chhzjtigzdotacutwcyo"
ENV_FILE = os.path.expanduser("~/.config/nawana/marketing.env")
MEDIA_BASE = "https://nawana.app/admin/media/"

STAGES = ("idea", "brief", "copy", "design", "review", "ready",
          "scheduled", "vetoed", "posting", "posted", "failed")
EVENT_KINDS = ("stage", "run_start", "run_end", "media", "scheduled", "veto",
               "post", "post_error", "metrics", "note")
CHANNELS = ("instagram", "threads", "community")
PHASES = ("upload", "release", "manual")

TEXT_COLS = {"version", "phase", "title_ko", "title_en", "one_message", "review_verdict",
             "caption_ko", "caption_en", "threads_text", "veto_reason", "ig_media_id",
             "ig_permalink", "threads_media_id", "threads_permalink", "community_news_id",
             "error", "stage"}
INT_COLS = {"build", "review_fixes"}
BOOL_COLS = {"show_in_community"}
TS_COLS = {"scheduled_at", "vetoed_at", "posted_at"}
JSON_COLS = {"slides"}
SETTABLE = TEXT_COLS | INT_COLS | BOOL_COLS | TS_COLS | JSON_COLS
METRIC_COLS = ("views", "reach", "likes", "comments", "saves", "shares")


# ── transport ────────────────────────────────────────────────────────────
_token = None


def token():
    global _token
    if _token is None:
        raw = subprocess.check_output(["security", "find-generic-password", "-s", "Supabase CLI", "-w"],
                                      text=True).strip()
        _token = base64.b64decode(raw.removeprefix("go-keyring-base64:")).decode()
    return _token


class DBError(RuntimeError):
    pass


def sql(query):
    """Run one SQL statement against production; returns the rows (list of dicts)."""
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT}/database/query",
        data=json.dumps({"query": query}).encode(),
        # api.supabase.com refuses the default Python-urllib User-Agent.
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json",
                 "User-Agent": "nawana-marketing-db"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise DBError(f"query failed ({e.code}): {e.read().decode()[:400]}") from None


def lit(s):
    """A SQL string literal no text can break out of (random dollar tag)."""
    if s is None:
        return "null"
    tag = "t" + secrets.token_hex(6)
    return f"${tag}${s}${tag}$"


# ── credentials file ─────────────────────────────────────────────────────
def load_env(path=ENV_FILE):
    """KEY=VALUE lines (optional `export`, optional quotes). Missing file = {}."""
    out = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                line = line.removeprefix("export ").strip()
                if "=" not in line:
                    continue
                k, v = line.split("=", 1)
                v = v.strip()
                if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
                    v = v[1:-1]
                out[k.strip()] = v
    except FileNotFoundError:
        pass
    return out


def write_env(updates, path=ENV_FILE):
    """Rewrite only the given keys in place (appending new ones); file stays 0600."""
    lines = []
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        os.makedirs(os.path.dirname(path), exist_ok=True)
    seen = set()
    for i, line in enumerate(lines):
        m = re.match(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=", line)
        if m and m.group(1) in updates:
            lines[i] = f"{m.group(1)}={updates[m.group(1)]}"
            seen.add(m.group(1))
    for k, v in updates.items():
        if k not in seen:
            lines.append(f"{k}={v}")
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, path)


def veto_hours(env=None):
    env = env if env is not None else load_env()
    try:
        return float(os.environ.get("VETO_HOURS") or env.get("VETO_HOURS") or 12)
    except ValueError:
        return 12.0


# ── helpers other scripts use ────────────────────────────────────────────
def piece(slug):
    rows = sql(f"select * from marketing_pieces where slug = {lit(slug)}")
    return rows[0] if rows else None


def require_piece(slug):
    p = piece(slug)
    if not p:
        raise DBError(f"no piece '{slug}' — create it with piece-upsert first")
    return p


def add_event(piece_id, kind, message):
    if kind not in EVENT_KINDS:
        raise DBError(f"unknown event kind '{kind}' (one of: {', '.join(EVENT_KINDS)})")
    pid = f"{lit(piece_id)}::uuid" if piece_id else "null"
    sql(f"insert into marketing_events (piece_id, kind, message) values ({pid}, {lit(kind)}, {lit(message)})")


def set_columns(piece_id, values):
    """values: {column: python value already validated}. Returns the updated row."""
    parts = []
    for col, v in values.items():
        if col not in SETTABLE:
            raise DBError(f"'{col}' is not a settable column")
        if v is None:
            parts.append(f"{col} = null")
        elif col in JSON_COLS:
            parts.append(f"{col} = {lit(json.dumps(v, ensure_ascii=False))}::jsonb")
        elif col in INT_COLS:
            parts.append(f"{col} = {int(v)}")
        elif col in BOOL_COLS:
            parts.append(f"{col} = {'true' if v else 'false'}")
        elif col in TS_COLS:
            parts.append(f"{col} = now()" if v == "now" else f"{col} = {lit(v)}::timestamptz")
        else:
            parts.append(f"{col} = {lit(str(v))}")
    rows = sql(f"update marketing_pieces set {', '.join(parts)} where id = {lit(piece_id)}::uuid returning *")
    return rows[0] if rows else None


def parse_value(col, raw):
    if raw == "null":
        return None
    if col in JSON_COLS:
        try:
            v = json.loads(raw)
        except json.JSONDecodeError as e:
            raise DBError(f"{col}: not JSON ({e})")
        if col == "slides" and not isinstance(v, list):
            raise DBError("slides must be a JSON array")
        return v
    if col in INT_COLS:
        if not re.fullmatch(r"-?\d+", raw):
            raise DBError(f"{col} must be an integer")
        return int(raw)
    if col in BOOL_COLS:
        if raw.lower() not in ("true", "false", "1", "0", "yes", "no"):
            raise DBError(f"{col} must be true/false")
        return raw.lower() in ("true", "1", "yes")
    if col == "stage" and raw not in STAGES:
        raise DBError(f"unknown stage '{raw}'")
    if col == "phase" and raw not in PHASES:
        raise DBError(f"unknown phase '{raw}'")
    return raw


def passed_review(p):
    return (p.get("review_verdict") or "").strip().upper().startswith("PASS")


def media_url(key):
    return MEDIA_BASE + key.lstrip("/")


# ── CLI ──────────────────────────────────────────────────────────────────
def cmd_piece_upsert(x):
    if x.phase and x.phase not in PHASES:
        raise DBError(f"unknown phase '{x.phase}'")
    cols = {"version": x.version, "build": x.build, "phase": x.phase,
            "title_ko": x.title_ko, "title_en": x.title_en, "one_message": x.one_message}
    given = {k: v for k, v in cols.items() if v is not None}
    names = ["slug"] + list(given)
    vals = [lit(x.slug)] + [str(int(v)) if k == "build" else lit(v) for k, v in given.items()]
    update = ", ".join(f"{k} = excluded.{k}" for k in given) or "slug = excluded.slug"
    r = sql(f"""insert into marketing_pieces ({', '.join(names)}) values ({', '.join(vals)})
                on conflict (slug) do update set {update}
                returning id, slug, stage, (xmax = 0) as inserted""")[0]
    print(f"{'created' if r['inserted'] else 'updated'} {r['slug']}  {r['id']}  stage={r['stage']}")


def cmd_stage(x):
    if x.stage not in STAGES:
        raise DBError(f"unknown stage '{x.stage}' (one of: {', '.join(STAGES)})")
    p = require_piece(x.slug)
    if x.stage in ("scheduled", "posting", "posted"):
        raise DBError(f"'{x.stage}' is set by `schedule` / the scheduler, not by hand")
    set_columns(p["id"], {"stage": x.stage})
    msg = f"{p['stage']} → {x.stage}" + (f": {x.note}" if x.note else "")
    add_event(p["id"], "stage", msg)
    print(f"{x.slug}: {msg}")


def cmd_set(x):
    p = require_piece(x.slug)
    values = {}
    for pair in x.pairs:
        if "=" not in pair:
            raise DBError(f"expected key=value, got '{pair}'")
        k, raw = pair.split("=", 1)
        k = k.strip()
        if k not in SETTABLE:
            raise DBError(f"'{k}' is not settable (one of: {', '.join(sorted(SETTABLE))})")
        if k in ("stage", "scheduled_at", "posted_at", "vetoed_at"):
            raise DBError(f"'{k}' moves through `stage` / `schedule` / the console, not `set`")
        values[k] = parse_value(k, raw)
    if not values:
        raise DBError("nothing to set")
    set_columns(p["id"], values)
    print(f"{x.slug}: set {', '.join(values)}")


def cmd_event(x):
    pid = None if x.slug == "-" else require_piece(x.slug)["id"]
    add_event(pid, x.kind, x.message)
    print(f"event {x.kind} {'(run)' if pid is None else x.slug}")


def cmd_schedule(x):
    p = require_piece(x.slug)
    if not passed_review(p):
        raise DBError(f"{x.slug}: no reviewer PASS (review_verdict={p.get('review_verdict')!r}) — not scheduling")
    if not p.get("slides"):
        raise DBError(f"{x.slug}: no slides registered — upload media first")
    if p["stage"] in ("posting", "posted"):
        raise DBError(f"{x.slug}: already {p['stage']}")
    hours = x.hours if x.hours is not None else veto_hours()
    r = sql(f"""update marketing_pieces
                   set stage = 'scheduled', scheduled_at = now() + make_interval(secs => {float(hours) * 3600}),
                       vetoed_at = null, veto_reason = null, error = null
                 where id = {lit(p['id'])}::uuid returning scheduled_at""")[0]
    add_event(p["id"], "scheduled", f"posts at {r['scheduled_at']} (veto window {hours:g} h)")
    print(f"{x.slug}: scheduled for {r['scheduled_at']}")


def cmd_list(x):
    where = []
    if x.stage:
        where.append(f"stage = {lit(x.stage)}")
    if x.version:
        where.append(f"version = {lit(x.version)}")
    w = ("where " + " and ".join(where)) if where else ""
    rows = sql(f"""select id, slug, version, build, phase, stage, title_ko, review_verdict,
                          scheduled_at, posted_at, jsonb_array_length(slides) as n_slides, error
                     from marketing_pieces {w} order by created_at desc limit 200""")
    if x.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return
    for r in rows:
        when = r["posted_at"] or r["scheduled_at"] or ""
        print(f"{r['slug']:<40} {r['stage']:<10} {r['version'] or '-':<8} {str(r['build'] or '-'):<5} "
              f"{r['n_slides']:>2} slides  {(r['review_verdict'] or '-')[:12]:<12} {str(when)[:16]}  {r['title_ko'] or ''}"
              + (f"  ! {r['error']}" if r["error"] else ""))
    if not rows:
        print("(no pieces)")


def cmd_slides_merge(x):
    """Merge slide entries by `n` into the piece's slides, keeping keys already there
    (alt_ko / alt_en written by the lead survive a media re-upload)."""
    p = require_piece(x.slug)
    new = parse_value("slides", x.slides_json)
    by_n = {s.get("n"): dict(s) for s in (p.get("slides") or []) if isinstance(s, dict)}
    for s in new:
        if not isinstance(s, dict) or "n" not in s:
            raise DBError("every slide needs an 'n'")
        by_n.setdefault(s["n"], {}).update({k: v for k, v in s.items() if v is not None})
    merged = [by_n[n] for n in sorted(by_n, key=lambda n: (n is None, n))]
    set_columns(p["id"], {"slides": merged})
    print(f"{x.slug}: {len(merged)} slides")


def cmd_get(x):
    print(json.dumps(require_piece(x.slug), ensure_ascii=False, indent=2))


def cmd_metrics_add(x):
    if x.channel not in CHANNELS:
        raise DBError(f"unknown channel '{x.channel}'")
    p = require_piece(x.slug)
    vals, raw = {}, None
    for pair in x.pairs:
        k, _, v = pair.partition("=")
        if k == "raw":
            raw = json.loads(v)
        elif k in METRIC_COLS:
            vals[k] = int(v)
        else:
            raise DBError(f"unknown metric '{k}' (one of: {', '.join(METRIC_COLS)}, raw)")
    insert_metrics(p["id"], x.channel, vals, raw)
    print(f"{x.slug} {x.channel}: {vals}")


def insert_metrics(piece_id, channel, vals, raw=None, replace_today=False):
    if replace_today:
        sql(f"""delete from marketing_metrics where piece_id = {lit(piece_id)}::uuid
                  and channel = {lit(channel)} and captured_at::date = (now() at time zone 'utc')::date""")
    cols = ["piece_id", "channel"] + [c for c in METRIC_COLS if vals.get(c) is not None] + ["raw"]
    v = [f"{lit(piece_id)}::uuid", lit(channel)] + [str(int(vals[c])) for c in METRIC_COLS if vals.get(c) is not None]
    v.append(f"{lit(json.dumps(raw, ensure_ascii=False))}::jsonb" if raw is not None else "null")
    sql(f"insert into marketing_metrics ({', '.join(cols)}) values ({', '.join(v)})")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("piece-upsert"); a.add_argument("slug")
    a.add_argument("--version"); a.add_argument("--build", type=int); a.add_argument("--phase")
    a.add_argument("--title-ko"); a.add_argument("--title-en"); a.add_argument("--one-message")

    a = sub.add_parser("stage"); a.add_argument("slug"); a.add_argument("stage"); a.add_argument("--note")
    a = sub.add_parser("set"); a.add_argument("slug"); a.add_argument("pairs", nargs="+")
    a = sub.add_parser("event"); a.add_argument("slug"); a.add_argument("kind"); a.add_argument("message")
    a = sub.add_parser("schedule"); a.add_argument("slug"); a.add_argument("--hours", type=float)
    a = sub.add_parser("list"); a.add_argument("--stage"); a.add_argument("--version"); a.add_argument("--json", action="store_true")
    a = sub.add_parser("get"); a.add_argument("slug")
    a = sub.add_parser("slides-merge"); a.add_argument("slug"); a.add_argument("slides_json")
    a = sub.add_parser("metrics-add"); a.add_argument("slug"); a.add_argument("channel"); a.add_argument("pairs", nargs="*")

    x = ap.parse_args(argv)
    fn = {"piece-upsert": cmd_piece_upsert, "stage": cmd_stage, "set": cmd_set, "event": cmd_event,
          "schedule": cmd_schedule, "list": cmd_list, "get": cmd_get,
          "slides-merge": cmd_slides_merge, "metrics-add": cmd_metrics_add}[x.cmd]
    try:
        fn(x)
    except DBError as e:
        sys.exit(f"✗ {e}")


if __name__ == "__main__":
    main()
