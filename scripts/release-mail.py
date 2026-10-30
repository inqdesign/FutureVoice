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

CAMPAIGN = "release-1.2.7"
# Thumbnails are static files on the site (web/mail/<campaign>/), never
# Supabase Storage. They must be DEPLOYED before a real send; --preview points
# at the repo copies instead.
IMG_DIR = os.path.join(os.path.dirname(HERE), "web", "mail", CAMPAIGN)
IMG_BASE = f"{SITE_URL}/mail/{CAMPAIGN}"
THUMBS = ["tutor.jpg", "bot.jpg", "core.jpg", "routine.jpg", "coach.jpg", "add.jpg"]  # one per FEATURES row, same order


# --------------------------------------------------------------------------
# Copy. Edit here. {version} is filled from app_release.
# --------------------------------------------------------------------------

SUBJECT = "나와나 {version}이 나왔습니다: 튜터 모드, 개인 튜터, 코어 · nawana {version} is here"

KO_HERO = "나와나 {version}이 나왔습니다"
KO_OPEN = [
    "안녕하세요, 나와나(nawana)입니다.",
    "지난 메일 이후 업데이트가 여러 번 쌓여, 이번 버전으로 한 번에 소개해 드립니다. "
    "가장 크게 달라진 것은 튜터 모드입니다. 미래의 내가 대화 상대에서 선생님이 됩니다.",
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
    "Several updates have landed since my last email, so here they all are in one go. "
    "The biggest change is tutor mode: your future self goes from someone to talk with to your teacher.",
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
KO_ANDROID = ("안드로이드", "안드로이드 테스트가 시작됐습니다",
    "안드로이드 폰에서도 나와나를 쓸 수 있게 되었고, 지금 비공개 테스트를 하고 있습니다.",
    "주위에 안드로이드 폰을 쓰면서 나와나를 좋아할 만한 친구가 있다면 소개해 주세요. "
    "친구의 Gmail 주소를 답장으로 보내 주시면 테스트에 초대하겠습니다.",
    "친구 소개하기", "안드로이드 테스트 친구 소개")
EN_ANDROID = ("Android", "The Android test has started",
    "nawana now runs on Android phones, and a closed test is under way.",
    "If you have a friend on Android who would love nawana, introduce them to me. "
    "Reply with their Gmail address and I'll invite them to the test.",
    "Introduce a friend", "Android test: a friend for you")

# (accent colour, ko tag, ko title, ko line, en tag, en title, en line)
FEATURES = [
    ("#00A3BF", "튜터 모드", "미래의 내가 선생님으로",
     "배우고 싶은 말을 알려 주시면 미래의 내가 과제 서너 개로 수업을 짭니다. "
     "과제마다 예시를 들려준 뒤 직접 말해 보게 하고, 실수 없이 말할 때까지 함께 연습합니다. "
     "주제를 하나씩 통과하면 마지막에 최종 점검이 있고, 멈춘 수업은 다음 통화에서 이어집니다. "
     "홈 화면의 링을 옆으로 넘기면 자유 대화와 튜터 모드를 바로 바꿀 수 있습니다.",
     "Tutor mode", "Your future self, now your tutor",
     "Tell it what you want to learn to say and your future self plans a lesson of three or four challenges. "
     "For each one it gives you an example, then has you say it yourself until you get it right. "
     "Pass the topics one by one and a final check waits at the end; a lesson you stop picks up on your next call. "
     "Swipe the ring on the Home Screen to switch between free talk and tutor mode."),
    ("#FF9F0A", "개인 튜터", "매일 오늘 할 일을",
     "대화 탭 오른쪽 아래에 개인 튜터가 생겼습니다. 매일 오늘 할 일을 정리해 주고, "
     "새 팟캐스트 에피소드나 내 관심사에 맞춘 읽을거리도 골라 줍니다. "
     "연습에 대해 궁금한 것은 무엇이든 '물어보기'로 물어보실 수 있습니다.",
     "Personal tutor", "Today's plan, every day",
     "A personal tutor now sits at the bottom right of the Talk tab. Each day it lays out what's on for today, "
     "and picks a new podcast episode or something to read on your interests. "
     "Anything you want to know about your practice, just tap Ask."),
    ("#F2994A", "코어", "30일을 채우면 내 큐브가",
     "30일 연속으로 말하면 다음 날을 기다리지 않고 바로 코어에 들어갑니다. "
     "들어가는 순간 큐브 색을 고르고, 이름과 이루고 싶은 것을 새겨 내 자리에 놓습니다. "
     "다른 멤버의 큐브에는 하트나 짧은 응원을 남길 수 있고, 내 자리에 응원이 오면 알림이 옵니다.",
     "The Core", "Thirty days, and a cube of your own",
     "Speak thirty days in a row and you enter the Core right away, no waiting for the next morning. "
     "As you enter, you pick a colour for your cube, carve your name and what you hope to achieve, and set it in your seat. "
     "Leave a heart or a short cheer on another member's cube, and you'll get a notification when one lands on yours."),
    ("#0A84FF", "루틴", "나만의 루틴",
     "매일 오는 전화의 시간과 요일을 정하고, 다시 말하기, 복습, 쉐도잉, 듣기, 스피치 중 하고 싶은 것을 골라 "
     "시간을 정하면 한 주 계획표가 됩니다. 대화 탭 위쪽의 '활동'을 누르면 열립니다. "
     "홈 화면에 '나의 루틴' 위젯을 두면 오늘 할 일이 보이고, 누르면 바로 시작합니다.",
     "Routine", "Your own routine",
     "Set the days and times of your daily call, then pick what else you want to do (say it again, review, "
     "shadowing, listening, speech) and when. That becomes your week. Tap Activity at the top of the Talk tab to open it. "
     "Add the My routine widget to your Home Screen to see what's on today; a tap starts it."),
    ("#30B05A", "대화", "막히면 한 문장",
     "질문에 막히면 '이렇게 말해 보세요'가 내 레벨에 맞는 한 문장을 띄워 줍니다. "
     "지금까지 나눈 대화와 내 프로필을 보고 제안하기 때문에, 내가 이미 한 말과 어긋나지 않습니다. "
     "빈칸에는 내 이야기를 넣으면 됩니다.",
     "Talk", "One sentence when you're stuck",
     "Stuck on a question? “Try saying” shows one sentence at your level. "
     "It reads the whole call and your profile, so it never contradicts what you've already said. "
     "Fill the blank with your own story."),
    ("#FF375F", "복습", "단어를 직접 넣기",
     "단어, 표현, 문장을 직접 입력해서 내 목록에 넣을 수 있습니다. "
     "입력하는 동안 이미 있는 것은 뜻과 함께 찾아 보여 드리니, 같은 카드가 두 번 생기지 않습니다.",
     "Review", "Add your own words",
     "Type in a word, an expression or a sentence and it goes on your list. "
     "As you type, anything already there shows up with its meaning, so nothing is added twice."),
]

FIXES_KO = [
    "처음 시작할 때 이루고 싶은 미래를 고를 수 있습니다. 유창한 나는 그 미래를 이미 살고 있는 사람처럼 이야기합니다. 나 → 프로필 → 나의 미래에서 바꿀 수 있습니다.",
    "교정 문장이 내 문장을 군데군데 고쳐 붙이는 대신, 내가 하려던 말을 내 수준에 맞게 다시 써 줍니다.",
    "다시 말하기에서 '내 대사'와 '양쪽 대사'를 골라, 미래의 나 대사까지 직접 말해 볼 수 있습니다.",
    "스피치 결과에서 틀린 곳을 원고 위에 빨간 펜으로 표시해 줍니다. '자기소개 해 주세요' 챌린지도 새로 열렸습니다.",
    "매일 오는 전화가 매번 같은 얘기를 하지 않습니다. 지난 대화, 가벼운 얘기, 오늘의 뉴스, 의견을 묻는 질문으로 돌아가며 걸려 오고, 거절한 다음 날에도 제때 옵니다.",
    "음성 인식이 잘못 알아들었다면 복습 카드의 ⋯에서 '잘못 들림'을 고르세요. 그 말은 점수에서 빠지고 카드도 정리됩니다.",
    "팟캐스트 에피소드 옆 책 버튼을 누르면 그 에피소드가 내 복습 교재가 됩니다.",
    "스페인어를 배울 수 있고, 영국·호주 영어나 스페인 억양을 고르면 미래의 나도 그곳에서 쓰는 단어로 말합니다.",
]
FIXES_EN = [
    "When you start, you can choose the future you want. Your fluent self talks like someone already living it. Change it any time in Me → Profile → My future.",
    "Corrections no longer patch your sentence here and there; they rewrite what you meant to say, at your level.",
    "In Say it again, choose “My lines” or “Both sides” and read your fluent self's lines too.",
    "Speech results mark your slips on the script in red pen, and a new “Introduce yourself” challenge is open.",
    "Your daily call takes turns between your last talk, light chat, today's news and a question asking your opinion, and it rings on time even after you declined one.",
    "If the speech recognition got you wrong, choose “Misheard” under ⋯ on a review card. That line leaves your score and its cards are cleared.",
    "Tap the book button next to a podcast episode and it becomes a review book of your own.",
    "You can now learn Spanish, and with a British, Australian or Castilian accent your fluent self uses the words people say there.",
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
