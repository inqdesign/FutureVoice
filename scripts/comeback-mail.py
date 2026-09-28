#!/usr/bin/env python3
"""A note to the people who came back (2026-09-28).

Who: signed-in accounts that opened the app again in the last two weeks after
at least four days away, and hold no live subscription. Found in PostHog
(`Application Opened` / `screen_viewed` days per identified distinct_id, gap
>= 4 days, return within 14 days), then checked against `user_subscriptions`.
Most of them tried the app in the launch week, when calls dropped and the
review side was thin, and came back to look. One of them (07ad19f0) came back
today, tapped a scenario card, met the paywall and left 27 s later. They are
listed by user id below, not re-queried, so a run tomorrow mails the same
people this list was written for.

The copy is the founder's own (합니다체, no em dash). It says what changed,
that the plans changed, that the app has real subscribers now, and offers more
time by hand over Threads / Instagram DM. No price, no code: the offer is a
conversation, not a coupon.

Layout: the older mails padded the page 20 px a side inside a 480 px column,
and Gmail on a phone adds its own margin around that, so the text ran in a
narrow strip. Here the side padding is 16 px and drops to 4 px under 480 px
(`.wrap`), the header is smaller, and the body is 16 px / 1.65.

  python3 scripts/comeback-mail.py --preview out.html   # render
  python3 scripts/comeback-mail.py                      # dry run: who gets it
  python3 scripts/comeback-mail.py --test me@x.com      # one real send
  python3 scripts/comeback-mail.py --send               # everyone, after approval

Resend's Idempotency-Key is `<campaign>:<email>`, so a re-run within 24 h
cannot mail anyone twice.
"""

import argparse
import html
import importlib.util
import json
import os
import time
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "comeback-2026-09-28"

# Filled in by the founder before --send; the buttons point here.
THREADS_URL = "https://www.threads.net/@TODO"
INSTAGRAM_URL = "https://www.instagram.com/TODO"

USER_IDS = [
    "e8e660dc-5a31-41ce-81d5-598bc19dd560",
    "c3675ec0-46c6-447c-b220-3d44ea0b6872",
    "b989b404-4d76-4176-82e1-6d7b2ce84eb6",
    "dd61cb0b-dc71-41ee-87f2-c2b19336acaa",
    "6de8ec4d-9c4d-4905-a9aa-127a0ca563a1",
    "07ad19f0-6383-4242-b03a-4bfe993409c3",
    "a680574d-b3c8-4fd7-9633-6a5e4dcf2723",
    "4c83a192-5684-48fb-a8ec-14e1d3faca44",
    "78f712af-8d48-4154-b5e9-9d6877034a13",
    "dc7b35f6-8c6b-48b0-b8f0-c190aa8cafac",
    "4ad353fe-df04-44a8-8af6-b066ad88c59d",
    "a32e7cfe-2d95-49f4-aa97-56e30ba0b205",
]

# --------------------------------------------------------------------------
# Copy. Edit here.
# --------------------------------------------------------------------------

SUBJECT = "나와나가 그동안 많이 좋아졌습니다"

OPEN = [
    "안녕하세요. 나와나를 만든 이응규입니다.",
    "오랜만에 나와나에 다시 들러 주셔서 고맙습니다. "
    "처음 써 보셨을 때보다 앱이 많이 개선되어, 달라진 점을 알려 드리고 싶었습니다.",
]

FEATURES = [
    ("통화 품질", "통화가 훨씬 안정적이고 자연스러워졌습니다."),
    ("Talk 설정", "목소리 속도와 편의 기능들을 원하시는 대로 조정할 수 있습니다."),
    ("주간 테스트", "한 주 동안 연습한 내용으로 나만의 테스트를 봅니다."),
    ("상황 연습", "상황 연습이 많이 개선되었습니다."),
    ("다시 말하기", "내가 했던 Talk을 더 자연스럽게 교정된 스크립트로 다시 연습할 수 있습니다."),
]

AFTER_FEATURES = "마음껏 연습하시기에 좋은 기능들이라 생각합니다."

MIDDLE = [
    "요금제도 변경이 있었습니다.",
    "무엇보다, 처음 오셨을 때보다 실제 사용자가 훨씬 많아졌고, "
    "월간·연간으로 구독해 주시는 분들이 생겨나고 있어 큰 힘을 얻고 있습니다.",
]

OFFER = ("혹시 아직 관심이 있으시고 조금 더 테스트해 보고 싶으시다면, 스레드 메시지나 "
         "인스타그램 DM으로 연락 주세요. 제가 바로 추가 시간을 드리고, 테스트해 보실 수 "
         "있게 도와드리겠습니다.")

CLOSE = [
    "이제 시작이지만, 그 어떤 서비스보다 더 좋은 서비스라고 자부합니다.",
    "함께해 주시면, 앞으로 이루고자 하시는 목표에 닿으실 수 있도록 최선을 다하겠습니다.",
    "고맙습니다.",
]

SIGN = "이응규 드림"
UNSUB = "더 이상 메일을 받고 싶지 않으시면 답장으로 알려 주세요."


def text_body() -> str:
    parts = list(OPEN)
    parts.append("\n".join(f"· {t}: {d}" for t, d in FEATURES))
    parts.append(AFTER_FEATURES)
    parts += MIDDLE
    parts.append(f"{OFFER}\n\n스레드: {THREADS_URL}\n인스타그램: {INSTAGRAM_URL}")
    parts += CLOSE
    parts += [SIGN, L.APP_STORE_URL, UNSUB]
    return "\n\n".join(parts)


def html_body() -> str:
    def p(s, color=L.INK, top=16, size="16px"):
        return (f'<p style="font-size:{size};line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def feature_rows():
        rows = []
        for i, (title, desc) in enumerate(FEATURES):
            border = "" if i == 0 else f"border-top:1px solid {L.SURF};"
            rows.append(
                f'<tr><td style="padding:12px 0;{border}">'
                f'<div style="font-size:15px;font-weight:700;color:{L.INK};line-height:1.4;">{html.escape(title)}</div>'
                f'<div style="font-size:15px;color:{L.DIM};line-height:1.55;margin-top:2px;">{html.escape(desc)}</div>'
                '</td></tr>')
        return (f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
                f'style="margin:20px 0 0;border-top:1px solid {L.SURF};border-bottom:1px solid {L.SURF};">'
                + "".join(rows) + '</table>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", L.INK, "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (
        p(OPEN[0], top=0) + p(OPEN[1])
        + feature_rows()
        + p(AFTER_FEATURES, top=18)
        + "".join(p(s) for s in MIDDLE)
        + p(OFFER, top=24)
        + '<div style="margin:16px 0 0;">'
        + button("스레드로 메시지", THREADS_URL, True)
        + button("인스타그램 DM", INSTAGRAM_URL, False)
        + '</div>'
        + p(CLOSE[0], top=22) + p(CLOSE[1], top=10) + p(CLOSE[2], top=22)
        + p(SIGN, color=L.DIM, top=6)
    )

    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
@media only screen and (max-width:480px) {{
  .wrap {{ padding:22px 4px 28px !important; }}
}}
</style></head><body style="margin:0;padding:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};">
    <tr><td align="center" class="wrap" style="padding:32px 16px 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};text-align:left;word-break:keep-all;">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 22px;">
            <tr>
              <td style="vertical-align:middle;padding-right:10px;">
                <a href="{L.SITE_URL}" style="text-decoration:none;">
                  <img src="{L.LOGO_URL}" width="36" height="36" alt="nawana"
                       style="display:block;width:36px;height:36px;border-radius:9px;">
                </a>
              </td>
              <td style="vertical-align:middle;font-size:17px;font-weight:700;letter-spacing:-.01em;color:{L.INK};">nawana</td>
            </tr>
          </table>
          {body}
          <div style="margin-top:32px;padding-top:14px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a>
            &nbsp;·&nbsp;
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="mailto:{L.REPLY_TO}" style="color:{L.FAINT};text-decoration:none;">{L.REPLY_TO}</a>
            <br>{html.escape(UNSUB)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def recipients() -> list[dict]:
    ids = ",".join(f"'{u}'" for u in USER_IDS)
    return L.sql(f"""
      select u.id::text as user_id,
             case when u.email like '%{L.RELAY}' and m.waitlist_email is not null
                  then m.waitlist_email else u.email end as email,
             s.status
        from auth.users u
        left join user_waitlist_mapping m on m.user_id = u.id
        left join user_subscriptions s on s.user_id = u.id
       where u.id in ({ids}) and u.deleted_at is null
       order by u.created_at""")


def send(key: str, to: str, idem: str) -> str:
    payload = {
        "from": L.FROM,
        "to": [to],
        "reply_to": L.REPLY_TO,
        "subject": SUBJECT,
        "text": text_body(),
        "html": html_body(),
        "headers": {
            "List-Unsubscribe": f"<mailto:{L.REPLY_TO}?subject=unsubscribe>",
            "X-Entity-Ref-ID": idem,
        },
        "tags": [{"name": "campaign", "value": CAMPAIGN}],
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


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--preview", metavar="FILE", help="write the HTML and exit")
    ap.add_argument("--test", metavar="EMAIL", help="send one real mail to EMAIL")
    ap.add_argument("--send", action="store_true", help="send to the list (after the copy is approved)")
    args = ap.parse_args()

    if args.preview:
        with open(args.preview, "w") as f:
            f.write(html_body())
        print(f"wrote {args.preview}\n\n--- subject ---\n{SUBJECT}\n\n--- text ---\n{text_body()}")
        return

    if (args.send or args.test) and "TODO" in THREADS_URL + INSTAGRAM_URL:
        raise SystemExit("THREADS_URL / INSTAGRAM_URL still say TODO")

    if args.test:
        print("sent test:", send(L.resend_key(), args.test, f"{CAMPAIGN}:test:{int(time.time())}"))
        return

    plan = []
    for r in recipients():
        if r["status"] in ("active", "trialing"):
            print(f"  skip  {r['user_id'][:8]}  subscribed ({r['status']})")
        elif not r["email"] or not L.EMAIL_RE.match(r["email"]):
            print(f"  skip  {r['user_id'][:8]}  no address")
        else:
            plan.append(r)
    for r in plan:
        print(f"  send  {r['user_id'][:8]}  {r['email']}")
    print(f"{len(plan)} to send" + ("" if args.send else "   DRY RUN"))
    if not args.send:
        return

    key = L.resend_key()
    for r in plan:
        email = r["email"]
        try:
            print(f"  sent  {email}  {send(key, email, f'{CAMPAIGN}:{email.lower()}')}")
        except Exception as e:
            print(f"  FAIL  {r['email']}: {e}")
        time.sleep(L.PER_SEND_PAUSE)


if __name__ == "__main__":
    main()
