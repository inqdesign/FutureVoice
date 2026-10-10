#!/usr/bin/env python3
"""Release mail: a new version is out, here is what it brings, please update.

Run from the repo root:

  python3 scripts/release-mail.py --dry-run             # who gets it
  python3 scripts/release-mail.py --preview out.html    # render
  python3 scripts/release-mail.py --test me@x.com       # one real send, no list
  python3 scripts/release-mail.py --limit 3             # a few at a time
  python3 scripts/release-mail.py                       # everyone
  python3 scripts/release-mail.py --to a@x.com b@y.com  # named people only

Who: accounts that used the app in the last `--days` (30) days — a client
event inside the window — with a reachable address (sign-in email, or the
mapped waitlist address behind an Apple relay). Accounts whose last event
already named the App Store build are skipped unless `--include-updated`;
they have nothing to do. Our own accounts, and accounts whose last event came
from Android (the button is an App Store link), are left out.

Unlike update-mail.py (a plain "you are on an old build" notice), this one
SELLS the update: the release's main features as cards, then the button.
The copy is per release; edit FEATURES / FIXES and CAMPAIGN for the next one.

Record: nothing is written to the DB. Every delivered mail is appended to a
local send log, ~/.nawana/mail-logs/<campaign>.json (user id, address, when,
the build they were on) — outside the repo because it holds addresses.
Resend's Idempotency-Key is `<campaign>:<email>`, so a re-run inside 24 h
cannot mail anyone twice.

Did it work? `--report` reads the send log against client_events: who has
since opened the app on the App Store build (and how long after the mail),
who opened it but is still on an old build, who hasn't been back. That is the
real outcome — a click on the button is neither necessary nor sufficient for
an update. `--backfill-log ISO_TIME` rebuilds the log for a send made before
the log existed, from the recipient list as it stood at that moment.

Copy is bilingual, Korean first in 합니다체 (a letter from the founder), then
English. No em dashes in the body. Plumbing is borrowed from update-mail.py.
"""

import argparse
import datetime
import html
import importlib.util
import json
import os
import time

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("update_mail", os.path.join(HERE, "update-mail.py"))
upd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(upd)

sql, latest = upd.sql, upd.latest
FROM, REPLY_TO, SITE_URL, APP_STORE_URL = upd.FROM, upd.REPLY_TO, upd.SITE_URL, upd.APP_STORE_URL
RELAY, EMAIL_RE, OURS = upd.RELAY, upd.EMAIL_RE, upd.OURS
INK, PAPER, SURF, DIM, FAINT, BLUE = upd.INK, upd.PAPER, upd.SURF, upd.DIM, upd.FAINT, upd.BLUE
FONT, MONO, FONT_FACE, LOGO_URL = upd.FONT, upd.MONO, upd.FONT_FACE, upd.LOGO_URL
FOOTER, TAGLINE, PER_SEND_PAUSE = upd.FOOTER, upd.TAGLINE, upd.PER_SEND_PAUSE

CAMPAIGN = "release-1.1.4"
# Thumbnails are static files on the site (web/mail/<campaign>/), never
# Supabase Storage. They must be DEPLOYED before a real send; --preview points
# at the repo copies instead.
IMG_DIR = os.path.join(os.path.dirname(HERE), "web", "mail", CAMPAIGN)
IMG_BASE = f"{SITE_URL}/mail/{CAMPAIGN}"
THUMBS = ["speech.jpg", "routine.gif", "everyday.jpg", "coach.jpg", "workbook.jpg"]  # routine alternates two shots (GIF; Outlook shows the first)  # one per FEATURES row, same order


# --------------------------------------------------------------------------
# Copy. Edit here. {version} is filled from app_release.
# --------------------------------------------------------------------------

SUBJECT = "나와나 {version}이 나왔습니다: 스피치, 나의 루틴, 일상 상황 · nawana {version} is here"

KO_HERO = "나와나 {version}이 나왔습니다"
KO_OPEN = [
    "안녕하세요, 나와나(nawana)입니다.",
    "그동안 보내 주신 의견을 하나하나 읽으며 이번 버전을 만들었습니다. "
    "새로 생긴 기능이 꽤 많아서, 가장 큰 것들만 골라 소개해 드립니다.",
]
KO_MORE_TITLE = "그리고 이런 것들도 좋아졌습니다"
KO_CTA = "App Store에서 업데이트하기"
KO_HOWTO = (
    "버튼을 누르면 App Store의 나와나 페이지가 열립니다. 「업데이트」가 보이면 눌러 주시고, "
    "「열기」만 보인다면 이미 최신 버전입니다. 설정 → App Store → 「앱 업데이트」를 켜 두시면 "
    "다음부터는 알아서 설치됩니다."
)
KO_TAIL = "써 보시고 좋았던 점도, 아쉬운 점도 이 메일에 답장으로 알려 주세요. 제가 직접 읽습니다."
KO_UNSUB = "더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요."
KO_SIGN = "나와나 드림"

EN_HERO = "nawana {version} is here"
EN_OPEN = [
    "Hello, this is nawana.",
    "I read every piece of feedback you sent while building this version. "
    "There is a lot that is new, so here are just the biggest pieces.",
]
EN_MORE_TITLE = "And a few more things got better"
EN_CTA = "Update on the App Store"
EN_HOWTO = (
    "The button opens nawana on the App Store. If you see “Update”, tap it; if it only says “Open”, "
    "you already have the latest version. Turn on Settings → App Store → “App Updates” "
    "and new versions will install on their own."
)
EN_TAIL = "Try it, and tell me what you liked and what you didn't by replying to this email. I read every one myself."
EN_UNSUB = "If you would rather not receive more mail from us, reply and let me know."
EN_SIGN = "nawana"

# (accent colour, ko tag, ko title, ko line, en tag, en title, en line)
FEATURES = [
    ("#7C4DDB", "새 탭", "스피치",
     "발표나 면접 원고를 소리 내어 읽어 보는 곳입니다. 프롬프터가 내 목소리 속도에 맞춰 흐르고, "
     "카메라를 켜면 원고와 얼굴이 함께 담긴 영상이 남습니다. 정확도·속도·쉼·군말을 채점하고, "
     "코치가 다음에 해 볼 것을 알려 줍니다.",
     "New tab", "Speech",
     "Practice a talk or an interview answer out loud. The prompter keeps pace with your voice, "
     "and with the camera on you get a video of your script and your face. You're scored on accuracy, "
     "pace, pauses and filler words, and a coach tells you what to try next."),
    ("#0A84FF", "새 기능", "나의 루틴",
     "한 주 계획을 시간표에 바로 놓고 끌어서 옮깁니다. 대화·복습·다시 말하기를 원하는 요일과 시간에 두면, "
     "매일 전화도 루틴의 대화 시간에 맞춰 울립니다.",
     "New", "My routine",
     "Plan your week right on a timetable and drag blocks to move them. Put talks, reviews and Say it again "
     "where you want them, and the daily call rings at your routine's talk times."),
    ("#30B05A", "초보자용", "일상 상황",
     "카페, 식당, 옷 가게, 병원 전화처럼 자주 마주치는 상황을 한 번 눌러 바로 연습합니다.",
     "For beginners", "Everyday",
     "Common situations like a café, a restaurant, a clothing store or calling a clinic, one tap to start."),
    ("#F2994A", "코치 모드", "이렇게 말해 보세요",
     "코치 모드를 켜면 미래의 내가 한 마디 할 때마다 내 레벨에 맞는 답 예시가 뜹니다. "
     "나만 아는 부분은 흐리게 비워 두고, 뜻은 한국어로 함께 보여 줍니다. "
     "처음 시작하는 분께는 미래의 내가 짧고 구체적인 질문을 하나씩 건넵니다.",
     "Coach mode", "Try saying",
     "With coach mode on, every line from your future self comes with an example answer at your level. "
     "The parts only you know are left faint for you to fill in, with the meaning in your own language. "
     "If you're just starting out, your future self asks one short, concrete question at a time."),
    ("#20A4A4", "복습", "새 복습 페이지와 PDF 워크북",
     "교재마다 단어·표현·쉐도잉·문법을 한눈에 보고 끝까지 마치기 쉬워졌습니다. "
     "교재를 PDF로 내보내면 바로 풀 수 있는 워크북이 됩니다.",
     "Review", "A new Review page and PDF workbooks",
     "See each book's words, expressions, shadowing and grammar at a glance, and finish it more easily. "
     "Export a book as a PDF and you get a workbook you can fill in right away."),
]

FIXES_KO = [
    "미래의 내가 문장 사이에서 숨을 쉬듯 더 자연스럽게 말합니다.",
    "통화 중에도 말하기 속도를 바꿀 수 있습니다.",
    "블루투스 기기가 근처에 있을 때 첫인사가 끊기던 문제, 예약 전화가 통화를 끊던 문제를 고쳤습니다.",
    "쉐도잉 결과가 훨씬 빨리 나옵니다.",
    "탭을 처음 열면 짧은 사용 가이드가 나옵니다.",
]
FIXES_EN = [
    "Your future self breathes between sentences and sounds more natural.",
    "You can change the speaking speed during a call.",
    "Fixed the greeting cutting off near Bluetooth devices, and scheduled calls cutting off a call in progress.",
    "Shadowing results show up much faster.",
    "Each tab opens with a short guide the first time.",
]


def text_body(version: str) -> str:
    def side(hero, opening, feats, more_title, fixes, cta, howto, tail, unsub, sign):
        out = [hero.format(version=version)] + opening
        for title, line in feats:
            out.append(f"■ {title}\n{line}")
        out.append(more_title + "\n" + "\n".join(f"· {f}" for f in fixes))
        out += [f"{cta}\n{APP_STORE_URL}", howto, tail, unsub, sign]
        return out

    ko = side(KO_HERO, KO_OPEN, [(f[2], f[3]) for f in FEATURES], KO_MORE_TITLE, FIXES_KO,
              KO_CTA, KO_HOWTO, KO_TAIL, KO_UNSUB, KO_SIGN)
    en = side(EN_HERO, EN_OPEN, [(f[5], f[6]) for f in FEATURES], EN_MORE_TITLE, FIXES_EN,
              EN_CTA, EN_HOWTO, EN_TAIL, EN_UNSUB, EN_SIGN)
    return "\n\n".join(ko + ["· · ·"] + en + [SITE_URL])


def html_body(version: str, img_base: str = IMG_BASE) -> str:
    def p(s, color=INK, top=14, size="16px"):
        return (f'<p style="font-size:{size};line-height:1.7;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def hero(s):
        return (f'<h1 style="font-size:26px;line-height:1.3;font-weight:700;letter-spacing:-.02em;'
                f'color:{INK};margin:0 0 18px;">{html.escape(s.format(version=version))}</h1>')

    def card(accent, tag, title, line, thumb, flip=False):
        # Half image, half text; the image swaps sides card by card.
        img = (f'<td width="50%" style="width:50%;padding:0;vertical-align:top;font-size:0;line-height:0;">'
               f'<img src="{img_base}/{thumb}" width="250" alt="{html.escape(title)}" '
               f'style="display:block;width:100%;height:auto;"></td>')
        txt = f"""<td width="50%" style="width:50%;padding:16px;vertical-align:middle;word-break:keep-all;">
                <span style="display:inline-block;font-family:{MONO};font-size:11px;letter-spacing:.04em;
                             color:{accent};background:{accent}14;border-radius:999px;padding:3px 9px;">{html.escape(tag)}</span>
                <div style="font-size:17px;font-weight:700;color:{INK};margin:8px 0 0;">{html.escape(title)}</div>
                <div style="font-size:14px;line-height:1.6;color:{DIM};margin:6px 0 0;">{html.escape(line)}</div>
              </td>"""
        cells = txt + img if flip else img + txt
        return f"""
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
                 style="margin:16px 0 0;background:#FFFFFF;border:1px solid {SURF};border-radius:18px;overflow:hidden;table-layout:fixed;">
            <tr>{cells}</tr>
          </table>"""

    def more(title, fixes):
        items = "".join(
            f'<tr><td style="vertical-align:top;color:{FAINT};padding:3px 10px 0 0;font-size:14px;">·</td>'
            f'<td style="font-size:14.5px;line-height:1.65;color:{DIM};padding:3px 0 0;">{html.escape(f)}</td></tr>'
            for f in fixes)
        return (f'<div style="font-size:15px;font-weight:700;color:{INK};margin:28px 0 6px;">{html.escape(title)}</div>'
                f'<table role="presentation" cellpadding="0" cellspacing="0">{items}</table>')

    def cta(label):
        return (f'<p style="margin:28px 0 0;"><a href="{APP_STORE_URL}" '
                f'style="display:inline-block;background:{BLUE};color:#ffffff;text-decoration:none;'
                f'font-size:16px;font-weight:600;padding:14px 24px;border-radius:999px;">{html.escape(label)}</a></p>')

    def side(hero_s, opening, feats, more_title, fixes, cta_label, howto, tail, unsub, sign):
        out = [hero(hero_s), p(opening[0], top=0)] + [p(s) for s in opening[1:]]
        out.append('<div style="height:10px;"></div>')
        out += [card(*f, t, flip=i % 2 == 1) for i, (f, t) in enumerate(zip(feats, THUMBS))]
        out.append(more(more_title, fixes))
        out.append(cta(cta_label))
        out.append(p(howto, color=DIM, top=16, size="13.5px"))
        out.append(p(tail, top=26))
        out.append(p(sign, color=DIM, top=18, size="15px"))
        out.append(p(unsub, color=FAINT, top=18, size="12.5px"))
        return "".join(out)

    ko = side(KO_HERO, KO_OPEN, [(f[0], f[1], f[2], f[3]) for f in FEATURES], KO_MORE_TITLE, FIXES_KO,
              KO_CTA, KO_HOWTO, KO_TAIL, KO_UNSUB, KO_SIGN)
    en = side(EN_HERO, EN_OPEN, [(f[0], f[4], f[5], f[6]) for f in FEATURES], EN_MORE_TITLE, FIXES_EN,
              EN_CTA, EN_HOWTO, EN_TAIL, EN_UNSUB, EN_SIGN)
    divider = f'<div style="margin:40px 0 36px;border-top:1px solid {SURF};"></div>'
    return f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>{FONT_FACE}</style></head><body style="margin:0;background:{PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{PAPER};padding:44px 20px 40px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:500px;">
        <tr><td style="font-family:{FONT};color:{INK};">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 30px;">
            <tr>
              <td style="vertical-align:middle;padding-right:14px;">
                <a href="{SITE_URL}" style="text-decoration:none;">
                  <img src="{LOGO_URL}" width="52" height="52" alt="nawana"
                       style="display:block;width:52px;height:52px;border-radius:13px;">
                </a>
              </td>
              <td style="vertical-align:middle;">
                <div style="font-size:21px;font-weight:700;letter-spacing:-.01em;color:{INK};">nawana</div>
                <div style="font-size:12px;color:{FAINT};margin-top:3px;font-family:{MONO};">{html.escape(TAGLINE)}</div>
              </td>
            </tr>
          </table>
          {ko}
          {divider}
          {en}
          <div style="margin-top:40px;padding-top:18px;border-top:1px solid {SURF};font-size:12px;line-height:1.7;color:{FAINT};">
            <a href="{SITE_URL}" style="color:{FAINT};text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="{APP_STORE_URL}" style="color:{FAINT};text-decoration:none;">App Store</a>
            &nbsp;·&nbsp;
            <a href="mailto:{REPLY_TO}" style="color:{FAINT};text-decoration:none;">{REPLY_TO}</a>
            <br>{html.escape(FOOTER)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


# --------------------------------------------------------------------------
# Recipients and sending.
# --------------------------------------------------------------------------

LOG_DIR = os.path.expanduser("~/.nawana/mail-logs")


def log_path() -> str:
    return os.path.join(LOG_DIR, f"{CAMPAIGN}.json")


def load_log() -> dict:
    try:
        with open(log_path()) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"campaign": CAMPAIGN, "sent": []}


def save_log(log: dict) -> None:
    os.makedirs(LOG_DIR, exist_ok=True)
    tmp = log_path() + ".tmp"
    with open(tmp, "w") as f:
        json.dump(log, f, ensure_ascii=False, indent=1)
    os.replace(tmp, log_path())


def log_sent(log: dict, target_build: int, r: dict, sent_at: str) -> None:
    log["target_build"] = target_build
    log["sent"] = [x for x in log["sent"] if x["user_id"] != r["user_id"]]
    log["sent"].append({"user_id": r["user_id"], "email": r["email"], "sent_at": sent_at,
                        "build_before": r["build"]})
    save_log(log)


def recipients_sql(days: int, as_of: str | None = None) -> str:
    now = f"'{as_of}'::timestamptz" if as_of else "now()"
    return f"""
with last as (
  select user_id,
         max(created_at) as seen,
         (array_agg(properties->>'build' order by created_at desc) filter (where properties ? 'build'))[1] as build,
         (array_agg(coalesce(properties->>'platform', 'ios') order by created_at desc))[1] as platform
    from client_events
   where created_at > {now} - interval '{int(days)} days'
     and created_at <= {now}
   group by user_id
)
select u.id::text as user_id,
       case when u.email like '%{RELAY}' then m.waitlist_email else u.email end as email,
       l.seen::date::text as last_seen,
       l.build,
       l.platform
  from last l
  join auth.users u on u.id = l.user_id
  left join user_waitlist_mapping m on m.user_id = u.id
 where u.deleted_at is null
   and not u.is_anonymous
   and u.email is not null
 order by l.seen desc
"""


def send(key: str, to: str, version: str, idem: str) -> str:
    import json
    import urllib.request
    payload = {
        "from": FROM,
        "to": [to],
        "reply_to": REPLY_TO,
        "subject": SUBJECT.format(version=version),
        "text": text_body(version),
        "html": html_body(version),
        "headers": {
            "List-Unsubscribe": f"<mailto:{REPLY_TO}?subject=unsubscribe>",
            "X-Entity-Ref-ID": idem,
        },
        "tags": [{"name": "campaign", "value": CAMPAIGN.replace(".", "-")}],
    }
    req = urllib.request.Request("https://api.resend.com/emails",
                                 data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Idempotency-Key", idem)
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def report() -> None:
    log = load_log()
    sent, target = log["sent"], log.get("target_build")
    if not sent:
        print(f"no send log at {log_path()}")
        return
    ids = ",".join(f"'{x['user_id']}'" for x in sent)
    since = min(x["sent_at"] for x in sent)
    rows = sql(f"""
select user_id::text as user_id,
       min(created_at) filter (where (properties->>'build')::int >= {int(target)}) as updated_at,
       max(created_at) as last_seen,
       (array_agg(properties->>'build' order by created_at desc) filter (where properties ? 'build'))[1] as build
  from client_events
 where user_id in ({ids})
   and created_at > '{since}'::timestamptz
   and coalesce(properties->>'platform', 'ios') <> 'android'
 group by user_id
""")
    seen = {r["user_id"]: r for r in rows}
    ts = lambda v: datetime.datetime.fromisoformat(str(v).replace("Z", "+00:00").replace(" ", "T"))
    updated, still_old, gone = [], [], []
    for x in sent:
        r = seen.get(x["user_id"])
        if r and r["updated_at"] and ts(r["updated_at"]) > ts(x["sent_at"]):
            updated.append((x, (ts(r["updated_at"]) - ts(x["sent_at"])).total_seconds() / 3600))
        elif r and ts(r["last_seen"]) > ts(x["sent_at"]):
            still_old.append((x, r))
        else:
            gone.append(x)
    n = len(sent)
    pct = lambda k: f"{k}/{n} ({100 * k / n:.0f}%)"
    print(f"{CAMPAIGN}: mailed {n}, target build {target}, first send {since}")
    print(f"  updated               {pct(len(updated))}")
    print(f"  opened, still old     {pct(len(still_old))}")
    print(f"  not back since        {pct(len(gone))}")
    if updated:
        hrs = sorted(h for _, h in updated)
        print(f"  hours mail → update   median {hrs[len(hrs) // 2]:.1f}, "
              f"within 24 h {sum(h <= 24 for h in hrs)}, within 72 h {sum(h <= 72 for h in hrs)}")
    print()
    for x, h in sorted(updated, key=lambda t: t[1]):
        print(f"  updated   {x['email']:40} {x['build_before'] or '?':>3} → {target}   {h:6.1f} h after")
    for x, r in still_old:
        print(f"  still old {x['email']:40} {x['build_before'] or '?':>3} → {r['build'] or '?':>3}   seen {str(r['last_seen'])[:16]}")
    for x in gone:
        print(f"  not back  {x['email']:40} {x['build_before'] or '?':>3}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dry-run", action="store_true", help="plan only: nothing sent")
    ap.add_argument("--preview", metavar="FILE", help="write the HTML and exit")
    ap.add_argument("--test", metavar="EMAIL", help="send one real mail to EMAIL; touches no list")
    ap.add_argument("--limit", type=int, help="send to at most N people")
    ap.add_argument("--to", nargs="+", metavar="EMAIL", help="only these addresses (must be in the list)")
    ap.add_argument("--days", type=int, default=30, help="used the app within this many days (default 30)")
    ap.add_argument("--include-updated", action="store_true",
                    help="also mail accounts whose last event already named the App Store build")
    ap.add_argument("--version", help="override the version printed (default: app_release)")
    ap.add_argument("--report", action="store_true", help="who updated since the mail (reads the send log)")
    ap.add_argument("--backfill-log", metavar="ISO_TIME",
                    help="write the send log for a send made at ISO_TIME before logging existed; sends nothing")
    args = ap.parse_args()

    if args.report:
        report()
        return

    if args.preview:
        v = args.version or latest()[1]
        with open(args.preview, "w") as f:
            f.write(html_body(v, img_base="file://" + IMG_DIR))
        print(f"wrote {args.preview}\n\nSubject: {SUBJECT.format(version=v)}\n\n--- text variant ---\n{text_body(v)}")
        return

    build, version = latest()
    version = args.version or version

    if args.test:
        mid = send(upd.resend_key(), args.test, version, idem=f"{CAMPAIGN}:test:{int(time.time())}")
        print(f"sent test to {args.test}: {mid}")
        return

    plan, skipped = [], []
    wanted = {e.lower() for e in args.to} if args.to else None
    for r in sql(recipients_sql(args.days, as_of=args.backfill_log)):
        email = r["email"]
        if not email:
            skipped.append((r["user_id"][:8] + "… (relay, no waitlist address)", "unreachable"))
            continue
        if email.lower() in OURS:
            skipped.append((email, "ours"))
            continue
        if not EMAIL_RE.match(email):
            skipped.append((email, "invalid address"))
            continue
        if r["platform"] == "android":
            skipped.append((email, "Android (the mail points at the App Store)"))
            continue
        if wanted is not None and email.lower() not in wanted:
            continue
        if not args.include_updated and r["build"] and int(r["build"]) >= build:
            skipped.append((email, f"already on {r['build']}"))
            continue
        plan.append(r)
    if wanted:
        for e in sorted(wanted - {r["email"].lower() for r in plan}):
            skipped.append((e, "not in the list"))
    if args.limit:
        plan = plan[:args.limit]

    print(f"App Store: {version} ({build}); used the app in the last {args.days} days")
    print(f"{len(plan)} to send" + (f" (limit {args.limit})" if args.limit else "") + f", {len(skipped)} skipped"
          + ("   DRY RUN" if args.dry_run else ""))
    for who, why in skipped:
        print(f"  skip  {who:45} {why}")
    for r in plan:
        print(f"  send  {r['email']:45} last seen {r['last_seen'] or '-':10} build {r['build'] or '?'}")
    if args.backfill_log:
        log = load_log()
        for r in plan:
            log_sent(log, build, r, args.backfill_log)
        print(f"\nwrote {len(plan)} rows to {log_path()}")
        return
    if args.dry_run or not plan:
        return

    key = upd.resend_key()
    log = load_log()
    ok = failed = 0
    for r in plan:
        try:
            mid = send(key, r["email"], version, idem=f"{CAMPAIGN}:{r['email'].lower()}")
        except Exception as e:  # one bad address must not stop the rest
            failed += 1
            print(f"  FAIL {r['email']}: {e}")
            continue
        ok += 1
        log_sent(log, build, r, datetime.datetime.now(datetime.timezone.utc).isoformat())
        print(f"  sent {r['email']}  {mid}")
        time.sleep(PER_SEND_PAUSE)
    print(f"\n{ok} sent, {failed} failed; a re-run within 24 h cannot double-send (Idempotency-Key)")


if __name__ == "__main__":
    main()
