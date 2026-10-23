#!/usr/bin/env python3
"""Asking a French-speaking learner who spent the twenty free minutes (2026-10-23).

Who: 7c654ccc (desireefidele3@gmail.com), app language fr, Cameroon, learning
German at A1, coach mode on. Signed up 2026-10-21; the first call felt "hard"
on the first-call check; two more calls the next day (10 and 15 min) spent the
pool, the last one wrapping itself up. On 1.2.1. No subscription, never
mailed before.

Same letter as 2ed2f038's, written in French (vous, French spacing, no em
dash). No extra questions and no dates or times of use (founder, 2026-10-23).

  python3 scripts/feedback-ask-mail-7c654ccc.py --preview out.html
  python3 scripts/feedback-ask-mail-7c654ccc.py            # dry run
  python3 scripts/feedback-ask-mail-7c654ccc.py --send     # after approval
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

CAMPAIGN = "feedback-ask-7c654ccc-2026-10-23"

THREADS_URL = "https://www.threads.com/@adaywithboram"
INSTAGRAM_URL = "https://ig.me/m/nawana.app"

USER_IDS = ["7c654ccc-d82a-435a-8e5b-7d83c0e886aa"]

# --------------------------------------------------------------------------
# Copy. Edit here.
# --------------------------------------------------------------------------

SUBJECT = "Vos 20 minutes avec nawana, qu’en avez-vous pensé ?"

OPEN = [
    "Bonjour,",
    "Je m’appelle Eunggyu Lee, c’est moi qui ai créé nawana. Merci beaucoup de l’avoir "
    "essayée. Vous avez utilisé toutes vos 20 minutes gratuites à parler avec votre moi fluide, "
    "et pour quelqu’un qui construit cette app, c’est une vraie joie.",
    "Après ces 20 minutes, c’est le moment où l’on décide de continuer avec un abonnement "
    "ou de s’arrêter là. C’est pour cela que je vous écris aujourd’hui : votre avis "
    "m’aiderait énormément à savoir dans quelle direction aller. Toute remarque compte, "
    "n’hésitez pas.",
]

QUESTIONS = [
    "Avez-vous vraiment besoin d’apprendre l’allemand, au point d’être prêt(e) à payer pour cela ?",
    "Les 20 minutes gratuites vous ont-elles suffi pour vous faire une idée ? "
    "Laquelle de ces formules vous conviendrait le mieux ?\n"
    "A. 20 minutes d’appel gratuites, puis vous décidez de vous abonner\n"
    "B. Paiement d’abord, puis 1 semaine d’essai gratuit, annulable à tout moment\n"
    "C. 10 minutes d’appel gratuites, puis paiement et 1 semaine d’essai gratuit, annulable à tout moment\n"
    "D. 20 minutes d’appel gratuites, puis paiement et 3 jours d’essai gratuit, annulable à tout moment",
    "Si vous payez déjà un autre service pour apprendre une langue, ou si vous seriez prêt(e) à le faire, "
    "auriez-vous envie de continuer avec nawana ?",
    "Si quelque chose vous a fait hésiter à vous abonner, qu’est-ce que c’était ? "
    "Le prix, la qualité de l’appel, la voix, le contenu des conversations, tout est bon à dire.",
    "Et si vous avez d’autres remarques, je les lirai avec plaisir.",
]

OFFER = ("Une ligne suffit. Vous pouvez répondre à ce mail, ou m’écrire sur Threads ou "
         "en message privé sur Instagram, comme vous préférez. Je lis chaque réponse.")

MIDDLE: list[str] = [
    "Et si 20 minutes ne vous ont pas suffi pour vous décider, dites-le-moi en répondant "
    "à ce mail : je vous offrirai du temps en plus, pour que vous puissiez essayer "
    "tranquillement avant de choisir.",
    "Le détail des abonnements se trouve dans l’app : sur l’écran d’accueil, touchez votre "
    "profil en haut à droite, puis la page d’abonnement.",
]

CLOSE = "Merci beaucoup pour votre temps, et belle journée à vous."
SIGN = "Eunggyu Lee"
UNSUB = "Si vous ne souhaitez plus recevoir de mails, répondez simplement pour me le dire."


N = "\u202f"


def text_body() -> str:
    parts = list(OPEN)
    parts.append("\n\n".join(f"{i}. {q}" for i, q in enumerate(QUESTIONS, 1)))
    parts.append(f"{OFFER}\n\nRépondre{N}: {L.REPLY_TO}\nThreads{N}: {THREADS_URL}\nInstagram{N}: {INSTAGRAM_URL}")
    parts += MIDDLE
    parts += [CLOSE, SIGN, L.APP_STORE_URL, UNSUB]
    return "\n\n".join(parts)


def html_body() -> str:
    def p(s, color=L.INK, top=16, size="16px"):
        return (f'<p style="font-size:{size};line-height:1.65;color:{color};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')

    def qp(i, q):
        first, *opts = q.split("\n")
        out = p(f"{i + 1}. {first}", top=(18 if i == 0 else 12))
        for o in opts:
            out += (f'<p style="font-size:15px;line-height:1.6;color:{L.DIM};margin:4px 0 0 18px;">'
                    f'{html.escape(o)}</p>')
        return out

    def _unused_feature_rows():
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
        p(OPEN[0], top=0) + "".join(p(s) for s in OPEN[1:])
        + "".join(qp(i, q) for i, q in enumerate(QUESTIONS))
        + p(OFFER, top=20)
        + '<div style="margin:16px 0 0;">'
        + button("Répondre", f"mailto:{L.REPLY_TO}", True)
        + button("Threads", THREADS_URL, False)
        + button("Instagram (message)", INSTAGRAM_URL, False)
        + '</div>'
        + "".join(p(s, top=(22 if i == 0 else 10)) for i, s in enumerate(MIDDLE))
        + p(CLOSE, top=22)
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
