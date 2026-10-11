#!/usr/bin/env python3
"""Post scheduled marketing pieces once their veto window is over (marketing/AUTOMATION.md §5).

Runs from launchd every 15 minutes (com.nawana.marketing-scheduler). Each run:

  1. refreshes the Instagram / Threads long-lived tokens if the last refresh is
     older than 7 days, writing the new token back to ~/.config/nawana/marketing.env;
  2. for every piece with stage 'scheduled', scheduled_at <= now(), vetoed_at null
     and a reviewer PASS: claims it (stage 'posting'), posts it to every CONFIGURED
     channel, then stage 'posted' — or 'failed' with `error`.

A channel without credentials is skipped with a `post_error` event; the community
page needs no posting (it reads `marketing_public`), so a piece whose social
channels are all unconfigured still becomes 'posted'. A channel that already has a
media id on the piece (a retry after a partial failure) is not posted twice.

    scheduler.py             # do it
    scheduler.py --dry-run   # print what would happen; writes nothing, posts nothing
"""
import argparse, fcntl, json, os, sys, time, urllib.error, urllib.parse, urllib.request
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import db  # noqa: E402

IG_HOST = "https://graph.instagram.com"
TH_HOST = "https://graph.threads.net"
POLL_TIMEOUT = 300          # seconds per container (a video item can take a couple of minutes)
POLL_EVERY = 5
REFRESH_EVERY = 7 * 86400
LOCK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "marketing", "logs", "scheduler.lock")


def log(*a):
    print(datetime.now().strftime("%F %T"), *a, flush=True)


class PostError(RuntimeError):
    pass


# ── HTTP ─────────────────────────────────────────────────────────────────
def http(method, url, params=None):
    params = {k: v for k, v in (params or {}).items() if v is not None}
    body = None
    if method == "GET":
        url = url + ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    else:
        body = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"User-Agent": "nawana-marketing-scheduler"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        # never echo the token back into a log
        raise PostError(f"{method} {url.split('?')[0]} → {e.code}: {detail}") from None
    except urllib.error.URLError as e:
        raise PostError(f"{method} {url.split('?')[0]} → {e.reason}") from None


# ── channels ─────────────────────────────────────────────────────────────
class Channel:
    name = ""
    id_col = permalink_col = ""

    def __init__(self, env):
        self.env = env

    def configured(self):
        raise NotImplementedError

    def item_url(self, slide):
        """(media_type, url) for one slide."""
        if slide.get("kind") == "video" and slide.get("mp4"):
            return "VIDEO", db.media_url(slide["mp4"])
        key = slide.get("jpg") or slide.get("png") or slide.get("jpg_web")
        if not key:
            raise PostError(f"slide {slide.get('n')} has no media key")
        return "IMAGE", db.media_url(key)

    def wait(self, container_id):
        deadline = time.time() + POLL_TIMEOUT
        while True:
            st = self.status(container_id)
            if st == "FINISHED":
                return
            if st in ("ERROR", "EXPIRED"):
                raise PostError(f"{self.name} container {container_id} {st}")
            if time.time() > deadline:
                raise PostError(f"{self.name} container {container_id} still {st} after {POLL_TIMEOUT}s")
            time.sleep(POLL_EVERY)


class Instagram(Channel):
    """Instagram API with Instagram Login (graph.instagram.com)."""
    name, id_col, permalink_col = "instagram", "ig_media_id", "ig_permalink"

    def __init__(self, env):
        super().__init__(env)
        self.v = env.get("IG_API_VERSION") or "v22.0"
        self.user, self.token = env.get("IG_USER_ID"), env.get("IG_ACCESS_TOKEN")

    def configured(self):
        return bool(self.user and self.token)

    def api(self, method, path, **params):
        return http(method, f"{IG_HOST}/{self.v}/{path}", {**params, "access_token": self.token})

    def status(self, cid):
        return self.api("GET", cid, fields="status_code,status").get("status_code", "UNKNOWN")

    def container(self, slide, carousel_item):
        mtype, url = self.item_url(slide)
        if mtype == "VIDEO":
            # a lone video must be a REEL; inside a carousel it is VIDEO
            p = {"media_type": "VIDEO" if carousel_item else "REELS", "video_url": url}
        else:
            p = {"image_url": url}
        if carousel_item:
            p["is_carousel_item"] = "true"
        return p

    def post(self, piece):
        slides = piece["slides"][:10]
        caption = caption_for(piece, self.env)
        if len(slides) == 1:
            cid = self.api("POST", f"{self.user}/media", caption=caption, **self.container(slides[0], False))["id"]
            self.wait(cid)
        else:
            # create every item first, then wait — videos process in parallel upstream
            children = [self.api("POST", f"{self.user}/media", **self.container(s, True))["id"] for s in slides]
            for c in children:
                self.wait(c)
            cid = self.api("POST", f"{self.user}/media", media_type="CAROUSEL",
                           children=",".join(children), caption=caption)["id"]
            self.wait(cid)
        mid = self.api("POST", f"{self.user}/media_publish", creation_id=cid)["id"]
        link = self.api("GET", mid, fields="permalink").get("permalink")
        return mid, link

    def refresh(self):
        r = http("GET", f"{IG_HOST}/refresh_access_token",
                 {"grant_type": "ig_refresh_token", "access_token": self.token})
        return r["access_token"], int(r.get("expires_in") or 0)


class Threads(Channel):
    name, id_col, permalink_col = "threads", "threads_media_id", "threads_permalink"

    def __init__(self, env):
        super().__init__(env)
        self.v = env.get("THREADS_API_VERSION") or "v1.0"
        self.user, self.token = env.get("THREADS_USER_ID"), env.get("THREADS_ACCESS_TOKEN")

    def configured(self):
        return bool(self.user and self.token)

    def api(self, method, path, **params):
        return http(method, f"{TH_HOST}/{self.v}/{path}", {**params, "access_token": self.token})

    def status(self, cid):
        return self.api("GET", cid, fields="status,error_message").get("status", "UNKNOWN")

    def container(self, slide, carousel_item, text=None):
        mtype, url = self.item_url(slide)
        p = {"media_type": mtype, ("video_url" if mtype == "VIDEO" else "image_url"): url}
        if carousel_item:
            p["is_carousel_item"] = "true"
        if text:
            p["text"] = text
        return p

    def post(self, piece):
        slides = piece["slides"][:10]
        text = (piece.get("threads_text") or "").strip()[:500] or None
        if len(slides) == 1:
            cid = self.api("POST", f"{self.user}/threads", **self.container(slides[0], False, text))["id"]
            self.wait(cid)
        else:
            children = [self.api("POST", f"{self.user}/threads", **self.container(s, True))["id"] for s in slides]
            for c in children:
                self.wait(c)
            cid = self.api("POST", f"{self.user}/threads", media_type="CAROUSEL",
                           children=",".join(children), text=text)["id"]
            self.wait(cid)
        mid = self.api("POST", f"{self.user}/threads_publish", creation_id=cid)["id"]
        link = self.api("GET", mid, fields="permalink").get("permalink")
        return mid, link

    def refresh(self):
        r = http("GET", f"{TH_HOST}/refresh_access_token",
                 {"grant_type": "th_refresh_token", "access_token": self.token})
        return r["access_token"], int(r.get("expires_in") or 0)


def caption_for(piece, env):
    """IG caption language: IG_CAPTION_LANG (ko default), the other one as a fallback."""
    first = (env.get("IG_CAPTION_LANG") or "ko").lower()
    order = ["caption_ko", "caption_en"] if first == "ko" else ["caption_en", "caption_ko"]
    for col in order:
        if (piece.get(col) or "").strip():
            return piece[col].strip()[:2200]
    return None


# ── token refresh ────────────────────────────────────────────────────────
PREFIX = {"instagram": "IG", "threads": "THREADS"}


def refresh_tokens(env, dry):
    now = int(time.time())
    for ch in (Instagram(env), Threads(env)):
        if not ch.configured():
            continue
        p = PREFIX[ch.name]
        last = int(env.get(f"{p}_TOKEN_REFRESHED_AT") or 0)
        if now - last < REFRESH_EVERY:
            continue
        if dry:
            log(f"[dry-run] would refresh the {ch.name} token (last refresh {last or 'never'})")
            continue
        try:
            new, expires_in = ch.refresh()
        except PostError as e:
            log(f"{ch.name} token refresh failed: {e}")
            safe_event(None, "note", f"{ch.name} token refresh failed: {e}")
            continue
        exp = now + expires_in if expires_in else 0
        upd = {f"{p}_ACCESS_TOKEN": new, f"{p}_TOKEN_REFRESHED_AT": str(now)}
        if exp:
            upd[f"{p}_TOKEN_EXPIRES_AT"] = str(exp)
        db.write_env(upd)
        env.update(upd)
        when = datetime.fromtimestamp(exp, timezone.utc).strftime("%F") if exp else "unknown"
        log(f"{ch.name} token refreshed, expires {when}")
        safe_event(None, "note", f"{ch.name} token refreshed, expires {when}")


def safe_event(piece_id, kind, msg):
    try:
        db.add_event(piece_id, kind, msg)
    except db.DBError as e:
        log(f"(event not recorded: {e})")


# ── the run ──────────────────────────────────────────────────────────────
def due_pieces():
    return db.sql("""select * from marketing_pieces
                      where stage = 'scheduled' and scheduled_at <= now() and vetoed_at is null
                      order by scheduled_at""")


def claim(piece_id):
    """scheduled → posting, atomically; False if the console vetoed it meanwhile."""
    r = db.sql(f"""update marketing_pieces set stage = 'posting'
                    where id = {db.lit(piece_id)}::uuid and stage = 'scheduled' and vetoed_at is null
                    returning id""")
    return bool(r)


def post_piece(piece, env, dry):
    slug, pid = piece["slug"], piece["id"]
    if not db.passed_review(piece):
        msg = f"no reviewer PASS (review_verdict={piece.get('review_verdict')!r}) — not posting"
        log(f"{slug}: {msg}")
        if not dry:
            db.set_columns(pid, {"stage": "failed", "error": msg})
            safe_event(pid, "post_error", msg)
        return
    if not piece.get("slides"):
        msg = "no slides registered"
        log(f"{slug}: {msg}")
        if not dry:
            db.set_columns(pid, {"stage": "failed", "error": msg})
            safe_event(pid, "post_error", msg)
        return

    channels = [Instagram(env), Threads(env)]
    if dry:
        for ch in channels:
            if piece.get(ch.id_col):
                log(f"[dry-run] {slug}: {ch.name} already posted ({piece[ch.id_col]})")
            elif not ch.configured():
                log(f"[dry-run] {slug}: {ch.name} not configured — would skip")
            else:
                items = [ch.item_url(s) for s in piece["slides"][:10]]
                log(f"[dry-run] {slug}: would post {len(items)} item(s) to {ch.name}:")
                for t, u in items:
                    log(f"            {t:<5} {u}")
        log(f"[dry-run] {slug}: community page shows it via marketing_public once posted")
        return

    if not claim(pid):
        log(f"{slug}: vetoed or moved while queued — skipped")
        return
    safe_event(pid, "stage", "scheduled → posting")

    errors = []
    for ch in channels:
        if piece.get(ch.id_col):
            continue
        if not ch.configured():
            safe_event(pid, "post_error", f"{ch.name} not configured")
            log(f"{slug}: {ch.name} not configured — skipped")
            continue
        try:
            mid, link = ch.post(piece)
            db.set_columns(pid, {ch.id_col: mid, ch.permalink_col: link})
            safe_event(pid, "post", f"{ch.name}: {link or mid}")
            log(f"{slug}: posted to {ch.name} {link or mid}")
        except Exception as e:  # anything — a piece must never be left in 'posting'
            errors.append(f"{ch.name}: {e}")
            safe_event(pid, "post_error", f"{ch.name}: {e}")
            log(f"{slug}: {ch.name} FAILED {e}")

    if errors:
        db.set_columns(pid, {"stage": "failed", "error": " | ".join(errors)[:2000]})
        safe_event(pid, "stage", "posting → failed")
    else:
        db.set_columns(pid, {"stage": "posted", "posted_at": "now", "error": None})
        safe_event(pid, "stage", "posting → posted")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="print what would happen; write and post nothing")
    x = ap.parse_args()

    os.makedirs(os.path.dirname(LOCK), exist_ok=True)
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("another scheduler run is still going — exiting")
        return

    env = db.load_env()
    refresh_tokens(env, x.dry_run)
    try:
        pieces = due_pieces()
    except db.DBError as e:
        log(f"query failed: {e}")
        sys.exit(1)
    if not pieces:
        if x.dry_run:
            log("[dry-run] nothing due")
        return
    for p in pieces:
        try:
            post_piece(p, env, x.dry_run)
        except db.DBError as e:
            log(f"{p['slug']}: database error {e}")


if __name__ == "__main__":
    main()
