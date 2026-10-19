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
import urllib.parse

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
THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

CAMPAIGN = "release-1.1.8"
# Thumbnails are static files on the site (web/mail/<campaign>/), never
# Supabase Storage. They must be DEPLOYED before a real send; --preview points
# at the repo copies instead.
IMG_DIR = os.path.join(os.path.dirname(HERE), "web", "mail", CAMPAIGN)
IMG_BASE = f"{SITE_URL}/mail/{CAMPAIGN}"
THUMBS = ["voice.jpg", "people.jpg", "profile.jpg", "challenge.jpg", "purpose.jpg", "effort.jpg"]  # one per FEATURES row, same order


# --------------------------------------------------------------------------
# Copy. Edit here. {version} is filled from app_release.
# --------------------------------------------------------------------------

SUBJECT = "나와나 {version}이 나왔습니다: 새 목소리, 새로운 사람들, 스피치 챌린지 · nawana {version} is here"

KO_HERO = "나와나 {version}이 나왔습니다"
KO_OPEN = [
    "안녕하세요, 나와나(nawana)입니다.",
    "지난 메일 이후 작은 업데이트를 몇 번 거쳐, 이번에 꽤 큰 버전이 나왔습니다. "
    "가장 크게 달라진 것은 목소리입니다. 하나씩 소개해 드립니다.",
]
KO_MORE_TITLE = "그리고 이런 것들도 좋아졌습니다"
KO_CTA = "App Store에서 업데이트하기"
KO_HOWTO = (
    "버튼을 누르면 App Store의 나와나 페이지가 열립니다. 「업데이트」가 보이면 눌러 주시고, "
    "「열기」만 보인다면 이미 최신 버전입니다. 설정 → App Store → 「앱 업데이트」를 켜 두시면 "
    "다음부터는 알아서 설치됩니다."
)
KO_TAIL = "써 보시고 좋았던 점도, 아쉬운 점도 알려 주세요. 이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다. 제가 직접 읽습니다."
KO_UNSUB = "더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요."
KO_SIGN = "나와나 드림"

EN_HERO = "nawana {version} is here"
EN_OPEN = [
    "Hello, this is nawana.",
    "A few small updates since my last email have added up to a big version. "
    "The biggest change is your voice. Here is what's new.",
]
EN_MORE_TITLE = "And a few more things got better"
EN_CTA = "Update on the App Store"
EN_HOWTO = (
    "The button opens nawana on the App Store. If you see “Update”, tap it; if it only says “Open”, "
    "you already have the latest version. Turn on Settings → App Store → “App Updates” "
    "and new versions will install on their own."
)
EN_TAIL = "Try it, and tell me what you liked and what you didn't. Reply to this email, or message me on Threads or Instagram. I read every one myself."
EN_UNSUB = "If you would rather not receive more mail from us, reply and let me know."
EN_SIGN = "nawana"

# The Android banner: news to celebrate, and the one thing we ask of readers.
# Play's closed test invites by Google account, hence the Gmail ask.
ANDROID_GREEN = "#34A853"
KO_ANDROID = ("안드로이드", "안드로이드 베타가 곧 시작됩니다",
    "드디어 안드로이드 폰에서도 나와나를 쓸 수 있게 됩니다. 곧 베타 테스트를 시작합니다. 함께 축하해 주세요!",
    "주위에 안드로이드 폰을 쓰면서 나와나를 좋아할 만한 친구가 있다면 소개해 주세요. "
    "친구의 Gmail 주소를 답장으로 보내 주시면 베타에 먼저 초대하겠습니다.",
    "친구 소개하기", "안드로이드 베타 친구 소개")
EN_ANDROID = ("Android", "The Android beta starts soon",
    "nawana is finally coming to Android phones, and the beta test starts soon. Celebrate with us!",
    "If you have a friend on Android who would love nawana, introduce them to me. "
    "Reply with their Gmail address and I'll invite them to the beta first.",
    "Introduce a friend", "Android beta: a friend for you")

# (accent colour, ko tag, ko title, ko line, en tag, en title, en line)
FEATURES = [
    ("#0A84FF", "목소리", "더 나 같은 목소리",
     "목소리를 새 음성 엔진으로 옮겼습니다. 더 자연스럽고 더 나 같은 목소리로 말하고, 대답도 빨라졌습니다. "
     "업데이트 후 앱을 열면 안내가 나옵니다. 악센트를 고르고 한 번 누르면 "
     "휴대폰에 있는 내 녹음으로 바로 다시 만들어집니다.",
     "Your voice", "More like you",
     "Your voice moves to a new voice engine. It sounds more natural and more like you, and replies come faster. "
     "Open the app after updating and you'll see a note: pick an accent, tap once, "
     "and your voice is rebuilt from the recording on your phone."),
    ("#FF375F", "상황연습", "새로운 사람, 새로운 이야기",
     "거리에서, 카페에서 처음 보는 사람과 말을 트듯, 유창한 내가 새로운 사람들을 만나 이야기를 나눕니다. "
     "나는 그 대화를 지켜보고, 거기서 나온 단어와 표현은 그대로 내 교재가 됩니다. "
     "새로운 사람을 만날수록 할 수 있는 이야기가 넓어집니다. 사람마다 자기 목소리와 억양으로 말합니다.",
     "Watch", "New people, new conversations",
     "Like striking up a conversation in a café or on the street, your fluent self meets new people and talks with them. "
     "You watch, and the words and expressions from each conversation become your own book. "
     "Every new person brings new topics, and more you can say. Each one speaks in their own voice and accent."),
    ("#FF9F0A", "사람 찾기", "유창한 나를 공개하기",
     "내 프로필을 공개해 두면, 다른 학습자들도 유창한 나와 자유롭게 이야기를 나눌 수 있습니다. "
     "이때는 내 목소리가 아니라, 우리나라 목소리 중에서 내가 직접 고른 목소리로 만납니다. "
     "내 목소리 그대로 만나게 하면 더 좋겠다는 생각도 있어서 아직 고민하고 있습니다. 어떻게 생각하시는지 들려주세요.",
     "Find people", "Let others meet your fluent self",
     "Make your profile public and other learners can talk freely with your fluent self. "
     "They meet it in a voice you pick from voices of your own country, not in your own voice. "
     "Meeting it in your own voice might be better, and I'm still thinking that through. Tell me what you think."),
    ("#7C4DDB", "스피치", "챌린지가 열렸습니다",
     "모두가 같은 원고를 읽고 점수로 순위를 겨룹니다. 지금 도전해서 순위표에 이름을 올려 보세요. "
     "몇 번이고 다시 읽을 수 있고, 가장 좋은 점수가 남습니다. 지금 1등이 누구인지 확인해 보세요.",
     "Speech", "Challenges are open",
     "Everyone reads the same script and competes for the top score. Take it on now and get your name on the leaderboard. "
     "Read it as many times as you like; your best score is the one that stays. Go see who's on top right now."),
    ("#30B05A", "대화", "나에게 맞는 주제",
     "왜 배우는지(시험, 면접, 일, 여행 등) 고르면 대화 탭의 주제가 그에 맞춰 바뀌고, 추천 루틴도 짜 드립니다.",
     "Talk", "Topics that fit you",
     "Choose why you're learning (an exam, an interview, work, travel and more) and the Talk tab's topics follow it, "
     "with a routine suggested for you."),
    ("#F2994A", "성장", "나의 노력",
     "성장 탭에서 '나의 노력'을 누르면 한 주, 한 달 동안 무엇을 얼마나 했는지 한눈에 볼 수 있습니다.",
     "Progress", "Your effort",
     "Tap “Your effort” on the Progress tab to see what you practised, and how much, over a week or a month."),
]

FIXES_KO = [
    "통화에서 답이 목소리와 함께 한 문장씩 화면에 나옵니다.",
    "섀도잉과 스피치 채점이 더 정확해졌습니다. 빠뜨린 부분은 원고에 적힌 그대로 보여 드립니다.",
    "주간 테스트에 새 문항이 생겼습니다. 내가 틀렸던 문법을 새 문장으로 연습합니다.",
    "나의 루틴에서 블록을 모두 시작했으면 지킨 날로 칩니다.",
    "목소리를 30일에 한 번만 바꿀 수 있던 제한이 없어졌습니다. 나 → 악센트에서 「그대로」를 고르면 원래 목소리로 돌아갑니다.",
    "Mac에서 통화가 연결되지 않던 문제, 나 탭을 열 때 앱이 닫히던 문제를 고쳤습니다.",
]
FIXES_EN = [
    "In a call, replies now appear one sentence at a time, together with the voice.",
    "Shadowing and Speech scores are more accurate, and anything you skipped is shown as it's written in the script.",
    "The weekly test has a new kind of question: the grammar you got wrong, practised in a new sentence.",
    "In My routine, a day counts once you've started every block.",
    "The limit of one voice change every 30 days is gone. Choose “Original” in Me → Accent to go back to your voice with no accent.",
    "Fixed calls not connecting on a Mac, and the app closing when you opened the Me tab.",
]


def text_body(version: str) -> str:
    def side(hero, opening, feats, more_title, fixes, cta, howto, tail, unsub, sign):
        out = [hero.format(version=version), f"{cta}\n{APP_STORE_URL}", howto] + opening
        a = KO_ANDROID if hero == KO_HERO else EN_ANDROID
        out.append(f"■ {a[1]}\n{a[2]}\n{a[3]}\n{REPLY_TO}")
        for title, line in feats:
            out.append(f"■ {title}\n{line}")
        out.append(more_title + "\n" + "\n".join(f"· {f}" for f in fixes))
        out += [f"{cta}\n{APP_STORE_URL}",
                f"{tail}\n\nThreads: {THREADS_URL}\nInstagram DM: {INSTAGRAM_URL}", unsub, sign]
        return out

    ko = side(KO_HERO, KO_OPEN, [(f[2], f[3]) for f in FEATURES], KO_MORE_TITLE, FIXES_KO,
              KO_CTA, KO_HOWTO, KO_TAIL, KO_UNSUB, KO_SIGN)
    en = side(EN_HERO, EN_OPEN, [(f[5], f[6]) for f in FEATURES], EN_MORE_TITLE, FIXES_EN,
              EN_CTA, EN_HOWTO, EN_TAIL, EN_UNSUB, EN_SIGN)
    return "\n\n".join(ko + ["· · ·"] + en + [SITE_URL])


# Phones: the page's side padding and the card's inner padding ate the text
# column (half of ~350 px). Narrow screens get thin gutters and a wider text cell.
MOBILE_CSS = """
@media only screen and (max-width:480px){
  .outer{padding:28px 12px 28px !important;}
  .card{table-layout:auto !important;direction:ltr !important;}
  .ci,.ct{display:block !important;width:100% !important;box-sizing:border-box !important;}
  .ci{background:#F2F2F7 !important;}
  .cimg{width:68% !important;margin:0 auto !important;}
  .ct{padding:16px 18px 18px !important;}
}"""


def html_body(version: str, img_base: str = IMG_BASE) -> str:
    def p(s, color=INK, top=14, size="16px"):
        return (f'<p style="font-size:{size};line-height:1.7;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def hero(s):
        return (f'<h1 style="font-size:26px;line-height:1.3;font-weight:700;letter-spacing:-.02em;'
                f'color:{INK};margin:0 0 18px;">{html.escape(s.format(version=version))}</h1>')

    def card(accent, tag, title, line, thumb, flip=False):
        # Half image, half text; the image swaps sides card by card.
        img = (f'<td class="ci" width="50%" style="width:50%;padding:0;vertical-align:top;font-size:0;line-height:0;">'
               f'<img class="cimg" src="{img_base}/{thumb}" width="250" alt="{html.escape(title)}" '
               f'style="display:block;width:100%;height:auto;"></td>')
        txt = f"""<td class="ct" dir="ltr" width="50%" style="width:50%;padding:16px;vertical-align:middle;word-break:keep-all;">
                <span style="display:inline-block;font-family:{MONO};font-size:11px;letter-spacing:.04em;
                             color:{accent};background:{accent}14;border-radius:999px;padding:3px 9px;">{html.escape(tag)}</span>
                <div style="font-size:17px;font-weight:700;color:{INK};margin:8px 0 0;">{html.escape(title)}</div>
                <div class="cl" style="font-size:14px;line-height:1.6;color:{DIM};margin:6px 0 0;">{html.escape(line)}</div>
              </td>"""
        # Image first in the source, always: a phone stacks the cells in source
        # order. The desktop zigzag comes from dir="rtl" on the row instead.
        cells = img + txt
        return f"""
          <table class="card" role="presentation" width="100%" cellpadding="0" cellspacing="0" dir="{'rtl' if flip else 'ltr'}"
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

    def cta(label, top=28):
        return (f'<p style="margin:{top}px 0 0;"><a href="{APP_STORE_URL}" '
                f'style="display:inline-block;background:{BLUE};color:#ffffff;text-decoration:none;'
                f'font-size:16px;font-weight:600;padding:14px 24px;border-radius:999px;">{html.escape(label)}</a></p>')

    def contact(reply, ig):
        def b(label, url):
            return (f'<a href="{url}" style="display:inline-block;color:{INK};border:1px solid #D9D6CE;'
                    f'text-decoration:none;font-size:14px;font-weight:600;padding:9px 16px;'
                    f'border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')
        return ('<div style="margin:14px 0 0;">' + b(reply, f"mailto:{REPLY_TO}")
                + b("Threads", THREADS_URL) + b(ig, INSTAGRAM_URL) + '</div>')

    def android(tag, title, news, ask, button, subject):
        g = ANDROID_GREEN
        href = f"mailto:{REPLY_TO}?subject={urllib.parse.quote(subject)}"
        return f"""
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
                 style="margin:22px 0 6px;background:{g}12;border:1px solid {g}40;border-radius:18px;">
            <tr><td style="padding:20px 20px 18px;word-break:keep-all;">
              <span style="display:inline-block;font-family:{MONO};font-size:11px;letter-spacing:.04em;
                           color:#FFFFFF;background:{g};border-radius:999px;padding:3px 10px;">{html.escape(tag)}</span>
              <div style="font-size:19px;font-weight:700;letter-spacing:-.01em;color:{INK};margin:10px 0 0;">{html.escape(title)}</div>
              <div style="font-size:15px;line-height:1.65;color:{INK};margin:8px 0 0;">{html.escape(news)}</div>
              <div style="font-size:14.5px;line-height:1.65;color:{DIM};margin:8px 0 0;">{html.escape(ask)}</div>
              <a href="{href}" style="display:inline-block;margin:14px 0 0;background:{g};color:#FFFFFF;text-decoration:none;
                 font-size:15px;font-weight:600;padding:11px 20px;border-radius:999px;">{html.escape(button)}</a>
            </td></tr>
          </table>"""

    def side(hero_s, opening, feats, more_title, fixes, cta_label, howto, tail, unsub, sign):
        # The update button leads (founder, 2026-10-13): the one thing the mail
        # asks for goes first; the cards below are why, and the button repeats.
        out = [hero(hero_s), cta(cta_label, top=0), p(howto, color=DIM, top=12, size="13.5px"),
               p(opening[0], top=28)] + [p(s) for s in opening[1:]]
        out.append(android(*(KO_ANDROID if hero_s == KO_HERO else EN_ANDROID)))
        out.append('<div style="height:10px;"></div>')
        out += [card(*f, t, flip=i % 2 == 1) for i, (f, t) in enumerate(zip(feats, THUMBS))]
        out.append(more(more_title, fixes))
        out.append(cta(cta_label))
        out.append(p(tail, top=26))
        out.append(contact(*(("답장하기", "인스타그램 DM") if hero_s == KO_HERO else ("Reply", "Instagram DM"))))
        out.append(p(sign, color=DIM, top=18, size="15px"))
        out.append(p(unsub, color=FAINT, top=18, size="12.5px"))
        return "".join(out)

    ko = side(KO_HERO, KO_OPEN, [(f[0], f[1], f[2], f[3]) for f in FEATURES], KO_MORE_TITLE, FIXES_KO,
              KO_CTA, KO_HOWTO, KO_TAIL, KO_UNSUB, KO_SIGN)
    en = side(EN_HERO, EN_OPEN, [(f[0], f[4], f[5], f[6]) for f in FEATURES], EN_MORE_TITLE, FIXES_EN,
              EN_CTA, EN_HOWTO, EN_TAIL, EN_UNSUB, EN_SIGN)
    divider = f'<div style="margin:40px 0 36px;border-top:1px solid {SURF};"></div>'
    return f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>{FONT_FACE}{MOBILE_CSS}</style></head><body style="margin:0;background:{PAPER};">
  <table class="outer" role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{PAPER};padding:44px 20px 40px;">
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
            &nbsp;·&nbsp;
            <a href="{THREADS_URL}" style="color:{FAINT};text-decoration:none;">Threads</a>
            &nbsp;·&nbsp;
            <a href="{INSTAGRAM_URL}" style="color:{FAINT};text-decoration:none;">Instagram</a>
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
