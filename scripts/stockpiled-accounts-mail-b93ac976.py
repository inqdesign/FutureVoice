#!/usr/bin/env python3
"""How is it going, and the free minutes are once per person (2026-11-17).

Who: b93ac976 (belsonata22), a Spanish speaker in Veracruz learning English
on Android. Made several accounts on 2026-11-15 and today; today on this one
they finished a 15-minute call and shadowed ten lines right after. The other
accounts' free minutes are being taken off (20261117220000).

The letter introduces the founder, says what we saw them do, says the free
minutes are once per person without accusing, asks whether sign-up went
wrong, and asks how the call felt. Spanish, tú. Copy is the founder's to
approve.

  python3 scripts/stockpiled-accounts-mail-b93ac976.py --preview out.html
  python3 scripts/stockpiled-accounts-mail-b93ac976.py            # dry run
  python3 scripts/stockpiled-accounts-mail-b93ac976.py --send     # after approval
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

CAMPAIGN = "stockpiled-accounts-2026-11-17"

USER_IDS = ["b93ac976-9b81-4928-85c4-f32a0ccf22fd"]

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

# --------------------------------------------------------------------------
# Copy. Edit here.
# --------------------------------------------------------------------------

SUBJECT = "¿Qué te pareció nawana?"

OPEN = [
    "Hola. Soy Eunggyu Lee y hago nawana. Soy coreano, vivo en Alemania "
    "y desarrollo la app yo solo.",
]

ACCOUNTS = [
    "Vi que estos días creaste varias cuentas.\n"
    "Si borraste una cuenta o empezaste de nuevo porque algo no funcionó al "
    "registrarte, cuéntame y lo reviso.\n"
    "Y ten en cuenta que al borrar una cuenta se borra todo lo que tenías "
    "guardado. Si quieres, puedes hacer una copia de seguridad en Google Drive "
    "o en iCloud.",
]

ASK = [
    "¿Qué te pareció la app hasta ahora?\n"
    "Me encantaría recibir cualquier comentario, sea el que sea.",
]

CLOSE = [
    "Puedes responder a este correo o escribirme por Threads o Instagram DM.",
]
SIGN = "Eunggyu Lee\nnawana"
UNSUB = "Si no quieres recibir más correos, responde a este mensaje."


def text_body() -> str:
    parts = list(OPEN)
    parts += ACCOUNTS
    parts += ASK
    parts += CLOSE
    parts.append(f"Threads: {THREADS_URL}\nInstagram DM: {INSTAGRAM_URL}")
    parts += [SIGN, L.SITE_URL, UNSUB]
    return "\n\n".join(parts)


def html_body() -> str:
    def p(s, color=L.INK, top=16, size="16px", weight="400"):
        return (f'<p style="font-size:{size};font-weight:{weight};line-height:1.7;color:{color};'
                f'margin:{top}px 0 0;">{html.escape(s).replace(chr(10), "<br>")}</p>')

    def button(label, url):
        return (f'<a href="{url}" style="display:inline-block;background:{L.BLUE};color:#ffffff;'
                f'border:1px solid {L.BLUE};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    def outline(label, url):
        return (f'<a href="{url}" style="display:inline-block;background:#ffffff;color:{L.BLUE};'
                f'border:1px solid {L.BLUE};text-decoration:none;font-size:15px;font-weight:600;'
                f'padding:11px 18px;border-radius:999px;margin:0 8px 8px 0;">{html.escape(label)}</a>')

    body = (
        p(OPEN[0], top=0) + "".join(p(s) for s in OPEN[1:])
        + "".join(p(s) for s in ACCOUNTS)
        + "".join(p(s, top=20) for s in ASK)
        + "".join(p(s, top=20) for s in CLOSE)
        + '<div style="margin:14px 0 0;">' + button("Responder", f"mailto:{L.REPLY_TO}")
        + outline("Threads", THREADS_URL) + outline("Instagram DM", INSTAGRAM_URL) + '</div>'
        + p(SIGN, color=L.DIM, top=18)
    )

    return f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
@media only screen and (max-width:480px) {{
  .wrap {{ padding:22px 4px 28px !important; }}
}}
</style></head><body style="margin:0;padding:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};">
    <tr><td align="center" class="wrap" style="padding:32px 16px 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};text-align:left;">
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
            <a href="{THREADS_URL}" style="color:{L.FAINT};text-decoration:none;">Threads</a>
            &nbsp;·&nbsp;
            <a href="{INSTAGRAM_URL}" style="color:{L.FAINT};text-decoration:none;">Instagram</a>
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

    if args.test:
        print("sent test:", send(L.resend_key(), args.test, f"{CAMPAIGN}:test:{int(time.time())}"))
        return

    plan = []
    for r in recipients():
        if not r["email"] or not L.EMAIL_RE.match(r["email"]):
            print(f"  skip  {r['user_id'][:8]}  no address")
        else:
            plan.append(r)
    for r in plan:
        print(f"  send  {r['user_id'][:8]}  {r['email']}  ({r['status']})")
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
