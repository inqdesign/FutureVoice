#!/usr/bin/env python3
"""Move every learner's voice to Cartesia (2026-10-13).

Drives the voice-move-all edge function one learner at a time. Where a
learner's ElevenLabs voice or recording is gone upstream, the recording from
the local archive (scripts/voice-archive.sh, ~/Desktop/beta audio/voices/
<name>-<voice_id>/) is sent along: an original clone take if any of their
voices has one, else the active remix's sample with its accent prompt.

  python3 scripts/voice-move-all.py              # dry run
  python3 scripts/voice-move-all.py --send       # move everyone
  python3 scripts/voice-move-all.py --send <user_id> ...
  python3 scripts/voice-move-all.py --send --days 5   # only learners seen in
      the last 5 days, most recent first; a voice already on Cartesia is made
      again from its original recording (now cleaned before cloning)
  python3 scripts/voice-move-all.py --send --reclone <user_id> ...   # same, these only

A learner who is talking, watching a scene or hearing their voice right now
(any talk tick, scene or TTS ledger row in the last BUSY_MINUTES) is skipped
and reported as "busy"; run again later for them. The old voice keeps
working anyway (nothing checks is_active, nothing is deleted), but a voice
that changes between two lines of one scene or call is not something to do
to someone mid-sentence.

Results are appended to /tmp/voice-move-all-<date>.jsonl.
"""

import base64
import glob
import json
import os
import subprocess
import sys
import time
import urllib.request

REF = "chhzjtigzdotacutwcyo"
ARCHIVE = os.path.expanduser("~/Desktop/beta audio/voices")
UA = {"User-Agent": "nawana-ops/1.0"}
BUSY_MINUTES = 5
BUSY_ACTIONS = ("talk_time", "tts", "tts_scene", "tts_timestamps")


def busy(uid: str) -> bool:
    acts = ",".join(f"'{a}'" for a in BUSY_ACTIONS)
    rows = query(f"""
        select 1 from usage_ledger where user_id = '{uid}'
          and created_at > now() - interval '{BUSY_MINUTES} minutes'
          and (action in ({acts}) or source_fn = 'gateway') limit 1""")
    return bool(rows)


def service_key() -> str:
    out = subprocess.run(["supabase", "projects", "api-keys", "--project-ref", REF, "-o", "json"],
                         capture_output=True, text=True, check=True).stdout
    return next(k["api_key"] for k in json.loads(out) if k.get("name") == "service_role")


def mgmt_token() -> str:
    raw = subprocess.run(["security", "find-generic-password", "-s", "Supabase CLI", "-w"],
                         capture_output=True, text=True, check=True).stdout.strip()
    return base64.b64decode(raw.removeprefix("go-keyring-base64:")).decode()


def query(sql: str):
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": sql}).encode(),
        headers={"Authorization": f"Bearer {mgmt_token()}", "Content-Type": "application/json", **UA})
    return json.load(urllib.request.urlopen(req))


def folder(voice_id: str):
    hits = glob.glob(os.path.join(glob.escape(ARCHIVE), f"*-{voice_id}"))
    return hits[0] if hits else None


def archived(voice_ids: list[str], active_id: str):
    """(b64, kind, accent_description) from the archive, or (None, None, desc)."""
    desc = None
    d = folder(active_id)
    if d and os.path.exists(os.path.join(d, "voice.json")):
        meta = json.load(open(os.path.join(d, "voice.json")))
        if meta.get("category") == "generated":
            desc = str(meta.get("description") or "")
    for vid in voice_ids:                      # newest first
        d = folder(vid)
        if not d:
            continue
        takes = sorted(glob.glob(os.path.join(d, "original-*.wav"))) + \
            sorted(glob.glob(os.path.join(d, "clonesample-*.mp3")))
        if takes:
            return base64.b64encode(open(takes[0], "rb").read()).decode(), "original", desc
    d = folder(active_id)
    if d and os.path.exists(os.path.join(d, "generated_audio.mp3")):
        return base64.b64encode(open(os.path.join(d, "generated_audio.mp3"), "rb").read()).decode(), "remix", desc
    return None, None, desc


def main():
    args = sys.argv[1:]
    send = "--send" in args
    days = None
    if "--days" in args:
        days = int(args[args.index("--days") + 1])
        args = [a for i, a in enumerate(args) if a != "--days" and (i == 0 or args[i - 1] != "--days")]
    reclone = days is not None or "--reclone" in args
    only = [a for a in args if a not in ("--send", "--reclone")]
    rows = query("""
        select v.user_id, v.elevenlabs_voice_id, v.is_active
        from voice_clones v join auth.users u on u.id = v.user_id
        where not coalesce(u.is_anonymous, false)
          and v.user_id in (select user_id from voice_clones where is_active)
        order by v.created_at desc""")
    by_user: dict[str, dict] = {}
    for r in rows:
        u = by_user.setdefault(r["user_id"], {"ids": [], "active": None})
        u["ids"].append(r["elevenlabs_voice_id"])
        if r["is_active"]:
            u["active"] = r["elevenlabs_voice_id"]
    users = only or list(by_user)
    if days is not None and not only:
        seen = query(f"""
            select u.id as user_id, greatest(
              (select max(updated_at) from auth.refresh_tokens r where r.user_id::uuid = u.id),
              (select max(refreshed_at) from auth.sessions s where s.user_id = u.id),
              u.last_sign_in_at) as last_seen
            from auth.users u where not coalesce(u.is_anonymous, false)""")
        recent = sorted((r for r in seen if r["last_seen"] and r["user_id"] in by_user
                         and r["last_seen"] >= time.strftime("%Y-%m-%d", time.gmtime(time.time() - days * 86400))),
                        key=lambda r: r["last_seen"], reverse=True)
        users = [r["user_id"] for r in recent]
        print(f"{len(users)} learners seen in the last {days} days", flush=True)
    key = service_key()
    out = f"/tmp/voice-move-all-{time.strftime('%Y%m%d')}.jsonl"
    for uid in users:
        info = by_user.get(uid)
        if not info or not info["active"]:
            continue
        if send and busy(uid):
            res = {"user_id": uid, "result": "busy"}
            print(json.dumps(res), flush=True)
            with open(out, "a") as f:
                f.write(json.dumps(res) + "\n")
            continue
        payload = {"user_id": uid, "dry": not send}
        if reclone and "-" in info["active"]:
            payload["reclone"] = True
            b64, kind, _ = archived([i for i in info["ids"] if "-" not in i], "")
            if b64 and kind == "original":
                payload.update(sample_b64=b64, sample_kind=kind)
        if "-" not in info["active"]:          # an ElevenLabs voice
            b64, kind, desc = archived([i for i in info["ids"] if "-" not in i], info["active"])
            if b64:
                payload.update(sample_b64=b64, sample_kind=kind)
            if desc:
                payload["accent_description"] = desc
        req = urllib.request.Request(
            f"https://{REF}.supabase.co/functions/v1/voice-move-all",
            data=json.dumps(payload).encode(),
            headers={"Authorization": f"Bearer {key}", "apikey": key, "Content-Type": "application/json", **UA})
        try:
            res = json.load(urllib.request.urlopen(req, timeout=150))
        except urllib.error.HTTPError as e:
            res = {"user_id": uid, "result": "http_error", "status": e.code, "body": e.read().decode()[:300]}
        except Exception as e:  # noqa: BLE001
            res = {"user_id": uid, "result": "request_failed", "detail": str(e)[:200]}
        line = json.dumps(res, ensure_ascii=False)
        print(line, flush=True)
        with open(out, "a") as f:
            f.write(line + "\n")
    print("→", out)


if __name__ == "__main__":
    main()
