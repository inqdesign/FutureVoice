#!/usr/bin/env python3
"""Before the renewal: an idle code subscriber, keep it or cancel it (2026-10-20).

Who: 019b115f (kylewskim@gmail.com). Beta tester, Plus monthly on the
Beta50 Plus Monthly v2 code (USA storefront, 9.99 USD), bought outside the
app. Used it only on 2026-09-15 (one ~5 min talk, a scene, shadowing),
nothing since. Auto-renew on; next charge 2026-10-22 17:59 UTC
(10-23 02:59 KST, 10-22 10:59 PDT).

Copy is the founder's to approve (합니다체, no em dash).

  python3 scripts/idle-subscriber-mail-019b115f.py --preview out.html
  python3 scripts/idle-subscriber-mail-019b115f.py            # dry run
  python3 scripts/idle-subscriber-mail-019b115f.py --send     # after approval
"""

import argparse
import html
import importlib.util
import json
import os
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "idle-subscriber-019b115f-2026-10-20"
TO = "kylewskim@gmail.com"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

SUBJECT = "구독이 갱신되기 전에 꼭 여쭙고 싶습니다"

PARAS = [
    "안녕하세요! nawana를 만들고 있는 이응규라고 합니다.",
    "처음 베타 테스트를 신청해 주시고, 감사하게도 구독 코드를 쓰셔서 가입해 주셨는데, "
    "한 달 동안 거의 사용하지 않으셨던 것 같습니다. 개인적으로는 정말 아쉽습니다. "
    "구독까지 해 주셨으니 잘 써 주셨으면 하는 마음이 있었거든요. "
    "이제 다음 구독이 결제되는 날이 다가오는데, 이번에도 사용하지 않으신다면 제가 미안한 마음이 들 것 같아서, "
    "꼭 한 번 더 말씀드려야겠다는 생각에 메일을 드립니다.",
    "할인 구독으로 가입하셔서 좋은 기회이긴 하니, 나중에 쓰실 생각으로 구독을 유지하고 계신 건지, "
    "아니면 취소하는 걸 깜빡하셔서 결제가 이어지는 건 아닌지 궁금합니다.",
    "혹시 깜빡하신 거라면, 아쉽지만 꼭 구독을 취소하셔서 낭비하시는 일이 없었으면 좋겠어요. "
    "물론 저도 돈을 벌려고 이 일을 하고 있지만, 사용하지 않는 분께 돈을 받는 건 아닌 것 같아서요.",
    "다음 결제는 한국 시간 10월 23일(금) 새벽 3시 직전(미국 서부 시간 10월 22일 오전 11시 직전)입니다. "
    "App Store 결제라 결제가 된 뒤에는 제가 되돌려 드릴 수가 없습니다. "
    "취소는 iPhone 설정 → 맨 위 이름 → 구독 → nawana → 구독 취소에서 하실 수 있습니다.",
    "물론 취소하셨다가 나중에 다시 오시면 할인 코드는 더 이상 쓰실 수 없습니다. "
    "떠나신다면 아쉽지만, 제 바람은 꼭 다시 오셔서 앱을 잘 써 주시는 것입니다.",
    "꼭 답장을 받을 수 있길 바랍니다!",
    "이 메일에 답장하셔도 되고, 스레드나 인스타그램 DM도 괜찮습니다.",
    "고맙습니다!",
]
SIGN = "이응규"
UNSUB = "메일을 받고 싶지 않으시면 답장으로 알려 주세요."


def text_body() -> str:
    return "\n\n".join(PARAS[:-1] + [
        f"답장: {L.REPLY_TO}\n스레드: {THREADS_URL}\n인스타그램 DM: {INSTAGRAM_URL}",
        PARAS[-1], SIGN, UNSUB])


def html_body() -> str:
    def p(s, color=L.INK, top=16):
        return (f'<p style="font-size:16px;line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def button(label, url, filled):
        bg, fg, bd = (L.BLUE, "#ffffff", L.BLUE) if filled else ("transparent", L.INK, "#D9D6CE")
        return (f'<a href="{url}" style="display:inline-block;background:{bg};color:{fg};'
                f'border:1px solid {bd};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (
        p(PARAS[0], top=0) + "".join(p(s) for s in PARAS[1:-1])
        + '<div style="margin:16px 0 0;">'
        + button("답장하기", f"mailto:{L.REPLY_TO}", True)
        + button("스레드", THREADS_URL, False)
        + button("인스타그램 DM", INSTAGRAM_URL, False)
        + '</div>'
        + p(PARAS[-1], top=18) + p(SIGN, color=L.DIM, top=6)
    )
    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};">
    <tr><td align="center" style="padding:32px 16px 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};text-align:left;">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 22px;"><tr>
            <td style="vertical-align:middle;padding-right:10px;"><a href="{L.SITE_URL}">
              <img src="{L.LOGO_URL}" width="36" height="36" alt="nawana"
                   style="display:block;width:36px;height:36px;border-radius:9px;"></a></td>
            <td style="vertical-align:middle;font-size:17px;font-weight:700;color:{L.INK};">nawana</td>
          </tr></table>
          {body}
          <div style="margin-top:32px;padding-top:14px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a> &nbsp;·&nbsp;
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a> &nbsp;·&nbsp;
            <a href="{THREADS_URL}" style="color:{L.FAINT};text-decoration:none;">Threads</a> &nbsp;·&nbsp;
            <a href="{INSTAGRAM_URL}" style="color:{L.FAINT};text-decoration:none;">Instagram</a>
            <br>{html.escape(UNSUB)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def send(key: str) -> str:
    idem = f"{CAMPAIGN}:{TO}"
    payload = {
        "from": L.FROM, "to": [TO], "reply_to": L.REPLY_TO,
        "subject": SUBJECT, "text": text_body(), "html": html_body(),
        "headers": {"List-Unsubscribe": f"<mailto:{L.REPLY_TO}?subject=unsubscribe>",
                    "X-Entity-Ref-ID": idem},
        "tags": [{"name": "campaign", "value": CAMPAIGN}],
    }
    req = urllib.request.Request("https://api.resend.com/emails",
                                 data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Idempotency-Key", idem)
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="FILE")
    ap.add_argument("--send", action="store_true")
    args = ap.parse_args()
    if args.preview:
        open(args.preview, "w").write(html_body())
    print(f"to       {TO}\nfrom     {L.FROM}\nsubject  {SUBJECT}\n")
    print(text_body())
    if not args.send:
        print("\nDRY RUN")
        return
    print("\nsent", send(L.resend_key()))


if __name__ == "__main__":
    main()
