#!/usr/bin/env python3
"""The welcome letter: thanks, how nawana began, the community, how to reach me.

  python3 scripts/welcome-mail.py --preview out/          # render every variant × language
  python3 scripts/welcome-mail.py --dry-run               # who would get what (broadcast)
  python3 scripts/welcome-mail.py --test me@x.com --lang ko --variant hello
  python3 scripts/welcome-mail.py --send --limit 3        # a few at a time
  python3 scripts/welcome-mail.py --send                  # everyone not yet mailed

Two variants of one letter:
  * signup — sent the moment an account exists (the edge function carries the
             same copy). Says "just now" and mentions the free first minutes.
  * hello  — the one-off broadcast to accounts that signed up before the letter
             existed. Same letter, opened as a belated hello, without the
             first-call section (most have talked; free minutes differ).

Language: `profiles.native_language` where `setup_at` says it was really chosen
(the column default is 'ko' for everyone). ko → Korean, any other choice →
English, no recorded choice → Korean then English in one mail.

Record: `welcome_mails` (one row per user) is claimed before the send and
stamped after Resend accepts. Re-runs skip anyone stamped.

Copy is the founder's: 합니다체, no em dashes. Edit here, never at send time.
"""

import argparse
import base64
import html
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

SUPABASE_PROJECT_REF = "chhzjtigzdotacutwcyo"
REPLY_TO = "hello@nawana.app"
SITE_URL = "https://nawana.app"
COMMUNITY_URL = f"{SITE_URL}/community"
APP_STORE_URL = "https://apps.apple.com/app/id6792794655"
THREADS_HANDLE = "adaywithboram"          # the founder's own; easiest to keep up with
THREADS_URL = f"https://www.threads.com/@{THREADS_HANDLE}"
INSTAGRAM_HANDLE = "nawana.app"
INSTAGRAM_DM_URL = f"https://ig.me/m/{INSTAGRAM_HANDLE}"
LOGO_URL = f"{SITE_URL}/mail/nawana-icon-256.png"
PER_SEND_PAUSE = 0.6
TEST_IDS = {  # admin/src/assemble.ts TEST_IDS
    "ecd78251-49c4-4e18-a156-6fbe90fd6e3b",
    "c5a85f25-a631-47c5-b32b-fb5bc89c551e",
    "5692cfc2-13ec-4f7e-a3bc-31daee02e28f",
    "b28ca7b1-dbd8-46de-bfd2-5857e05665bc",
}

# --------------------------------------------------------------------------
# Copy.
# --------------------------------------------------------------------------

COPY = {
    "ko": {
        "from": "이응규 · nawana <hello@nawana.app>",
        "subject": {"signup": "나와나에 오신 것을 환영합니다",
                    "hello": "나와나를 만든 이응규입니다"},
        "hi": "안녕하세요, 나와나를 만든 이응규입니다.",
        "thanks": {
            "signup": "나와나에 가입해 주셔서 정말 고맙습니다. 방금 들으신 그 목소리, "
                      "내 목소리로 유창하게 말하는 미래의 나를 이제 언제든 만나실 수 있습니다.",
            "hello": "나와나와 함께해 주셔서 정말 고맙습니다. 가입하셨을 때 제대로 인사를 드리지 못했는데, "
                     "늦었지만 이렇게 편지로 인사드립니다.",
        },
        "story_h": "어떻게 만들게 됐는지",
        "story": [
            "저는 대학교 2학년 때 영어가 꼭 필요하다는 생각에 영국으로 편입했고, 졸업 후 독일에서 "
            "일자리를 구해 지금 16년째 살고 있습니다. 클라이언트 미팅도, 프로젝트도, 팀 관리도 전부 영어로 해 왔습니다.",
            "그런데도 유창하다고 느낀 적은 한 번도 없었습니다. 상황은 넘길 수 있었지만, "
            "하고 싶은 말을 하고 싶은 방식으로 하지는 못했습니다.",
            "그래서 제게 가장 필요한 건, 내 생각을 입으로 말해 보는 연습이라고 생각했습니다.",
            "그런데 말하기 연습은 늘 남의 목소리를 흉내 내는 일이었습니다. 원어민의 발음을 따라 할 때마다 "
            "어색하고 나와 맞지 않았고, 꼭 연기를 하는 것 같아 불편했습니다.",
            "그 무렵 다른 앱을 만들면서 목소리가 가진 신비로운 힘을 더 절실히 느꼈습니다. 그리고 이런 생각이 "
            "들었습니다. 말하는 리듬도, 톤도, 음색도 그대로인 그냥 내 목소리인데, 영어를 완벽하게 말하는 내가 "
            "있다면 어떨까. 그 모습이 곧 내가 이루고 싶은 목표가 되지 않을까. 그렇다면 매일 그 목소리를 닮아 "
            "가도록 노력하면 되겠다.",
            "나와나는 그 생각에서 시작했습니다. 저도 지금 매일 이 앱으로 연습하고 있습니다.",
        ],
        "first_h": "처음이라면",
        "first": "Talk에서 첫 통화를 걸어 보세요. 주제 없이 편하게 말을 걸면 됩니다. 미래의 내가 먼저 "
                 "자기소개를 하고, 나에 대해 들은 이야기를 기억했다가 다음 통화에서 이어갑니다. 처음 20분은 무료입니다.",
        "comm_tag": "NEW · 커뮤니티",
        "comm_intro": "나와나 커뮤니티를 새로 열었습니다. 여기에는 세 가지가 있습니다.",
        "comm_items": [
            ("새 소식", "업데이트와 새 기능을 가장 먼저 알려 드립니다."),
            ("기능 소개", "기능마다 실제 앱 화면으로 쓰는 법을 보여 드립니다."),
            ("채팅", "다른 학습자들과 제가 함께 있습니다. 궁금한 점, 바라는 기능 무엇이든 남겨 주세요."),
        ],
        "comm_cta": "커뮤니티 둘러보기",
        "reach_h": "저에게 바로 말 걸기",
        "reach": "쓰시다가 막히는 곳, 좋았던 순간, 불편했던 점 모두 듣고 싶습니다. 편하신 곳으로 연락 주세요. "
                 "제가 직접 읽고 답합니다.",
        "reply": "이 메일에 답장",
        "threads": "Threads",
        "instagram": "Instagram DM",
        "notice": [
            "기존 유저분들께서는 구독 정책이 많이 바뀌어서 혼란이 있으셨을 거예요. 처음이라 자리 잡는 데까지 "
            "조금 너그럽게 이해해 주시길 바랍니다.",
            "꼭 최신 앱으로 업데이트해 주셔야 합니다. 그리고 혹시 무료 통화가 더 필요하신 분은 개인적으로 "
            "메시지를 주시면, 더 경험해 보실 수 있도록 도와드리겠습니다.",
        ],
        "update_cta": "App Store에서 최신 버전 받기",
        "close": "아직 부족한 곳이 많지만, 정말 열심히 만들고 있습니다. 미래의 나와 매일 조금씩 가까워지시길 바랍니다.",
        "sign": "이응규 드림",
        "foot": {"signup": "이 메일은 나와나 가입 시 한 번만 발송됩니다.",
                 "hello": "이 메일은 한 번만 발송됩니다. 더 받고 싶지 않으시면 답장으로 알려 주세요."},
    },
    "en": {
        "from": "Eunggyu from nawana <hello@nawana.app>",
        "subject": {"signup": "Welcome to nawana",
                    "hello": "A note from the person who made nawana"},
        "hi": "Hello, I'm Eunggyu Lee, the person who made nawana.",
        "thanks": {
            "signup": "Thank you so much for signing up. The voice you just heard, you speaking fluently "
                      "in your own voice, is there whenever you want to talk.",
            "hello": "Thank you so much for being part of nawana. I never properly said hello when you "
                     "signed up, so, a little late, here is my letter.",
        },
        "story_h": "How it began",
        "story": [
            "In my second year of university I transferred to a university in the UK, because I knew I "
            "would need English. After graduating I found a job in Germany, where I have now lived for "
            "16 years. Client meetings, projects, managing a team: I have done all of it in English.",
            "And yet I have never once felt fluent. I could get through the situation, but I could never "
            "say what I wanted to say, the way I wanted to say it.",
            "So I thought what I needed most was practice putting my own thoughts into spoken words.",
            "But speaking practice always meant imitating someone else's voice. Every time I copied a "
            "native speaker it felt awkward and not like me, as if I were acting, and I was never "
            "comfortable with it.",
            "Around then, while building another app, I felt more keenly than ever how strangely powerful "
            "a voice is. And a thought came to me. What if there were a me with my own rhythm, my own tone, "
            "my own timbre, just my voice, speaking perfect English? Wouldn't that become the very goal I "
            "want to reach? Then all I would need to do is work every day to sound like that voice.",
            "That is where nawana began. I practise with it every day too.",
        ],
        "first_h": "If you're just starting",
        "first": "Make your first call in Talk. No topic needed, just start talking. Your future self "
                 "introduces itself first, remembers what you tell it, and picks it up again on your next "
                 "call. Your first 20 minutes are free.",
        "comm_tag": "NEW · Community",
        "comm_intro": "I've just opened the nawana community. There are three things there.",
        "comm_items": [
            ("News", "Updates and new features, before anywhere else."),
            ("Feature guides", "How each feature works, shown on real app screens."),
            ("Chat", "Other learners and I are there. Ask anything, or tell us what you'd like to see."),
        ],
        "comm_cta": "Visit the community",
        "reach_h": "Talk to me directly",
        "reach": "Where you got stuck, what you loved, what bothered you: I want to hear all of it. "
                 "Reach me wherever is easiest. I read and answer every message myself.",
        "reply": "Reply to this email",
        "threads": "Threads",
        "instagram": "Instagram DM",
        "notice": [
            "If you've been with us for a while, the many changes to our subscription plans may have been "
            "confusing. We're new at this, and I ask for a little patience while things settle.",
            "Please make sure you're on the latest version of the app. And if you'd like more free call time, "
            "send me a message personally and I'll help you get to experience more of it.",
        ],
        "update_cta": "Get the latest version on the App Store",
        "close": "It is still far from perfect, but I'm building it with everything I have. "
                 "I hope you get a little closer to your future self every day.",
        "sign": "Eunggyu",
        "foot": {"signup": "This email is sent once, when you sign up for nawana.",
                 "hello": "This email is sent once. If you'd rather not hear from us, just reply and let me know."},
    },
}

BOTH_SUBJECT = {"signup": "나와나에 오신 것을 환영합니다 · Welcome to nawana",
                "hello": "나와나를 만든 이응규입니다 · A note from the maker of nawana"}

INK, PAPER, SURF, DIM, FAINT, BLUE = "#141310", "#FCFBF8", "#F0EFE9", "#57544D", "#918E85", "#0A5CF5"
FONT = "'Helvetica Neue',Helvetica,-apple-system,'Apple SD Gothic Neo',Arial,sans-serif"
MONO = "ui-monospace,'SF Mono',Menlo,'Roboto Mono',monospace"
PIXEL = f"'Geist Pixel',{FONT}"
FONT_FACE = (f"@font-face{{font-family:'Geist Pixel';font-style:normal;font-weight:400;"
             f"font-display:swap;src:url({SITE_URL}/GeistPixel.ttf) format('truetype');}}")


def e(s: str) -> str:
    return html.escape(s)


def section_html(c: dict, variant: str) -> str:
    def p(s, top=14, color=INK, size="16px"):
        return f'<p style="font-size:{size};line-height:1.7;color:{color};margin:{top}px 0 0;">{e(s)}</p>'

    def label(s):
        return (f'<p style="font-size:13px;letter-spacing:.04em;color:{FAINT};margin:34px 0 0;'
                f'font-family:{MONO};">{e(s)}</p>')

    out = [p(c["hi"], top=0), p(c["thanks"][variant])]
    out.append(label(c["story_h"]))
    out += [p(s, top=10 if i == 0 else 14) for i, s in enumerate(c["story"])]
    if variant == "signup":
        out += [label(c["first_h"]), p(c["first"], top=10)]
    items = "<br>".join(f"<b>{e(h)}</b>&nbsp; {e(t)}" for h, t in c["comm_items"])
    out.append(
        f'<div style="margin:34px 0 0;padding:22px 22px 24px;background:{SURF};border-radius:16px;">'
        f'<div style="font-size:12px;letter-spacing:.04em;color:{DIM};font-family:{MONO};">{e(c["comm_tag"])}</div>'
        f'<div style="font-size:22px;margin-top:8px;font-family:{PIXEL};">'
        f'<a href="{COMMUNITY_URL}" style="color:{INK};text-decoration:none;">nawana.app/community</a></div>'
        f'<p style="font-size:15px;line-height:1.7;margin:12px 0 0;">{e(c["comm_intro"])}</p>'
        f'<p style="font-size:15px;line-height:1.8;margin:8px 0 0;">{items}</p>'
        f'<p style="margin:18px 0 0;"><a href="{COMMUNITY_URL}" style="display:inline-block;background:{BLUE};'
        f'color:#ffffff;text-decoration:none;font-size:15px;font-weight:600;padding:11px 20px;'
        f'border-radius:999px;">{e(c["comm_cta"])}</a></p></div>')
    out += [label(c["reach_h"]), p(c["reach"], top=10)]

    def row(left, right, href):
        cell = f"padding:13px 0;border-bottom:1px solid {SURF};"
        return (f'<tr><td style="{cell}font-size:15px;"><a href="{href}" style="color:{INK};text-decoration:none;">'
                f'{e(left)}</a></td><td align="right" style="{cell}font-size:14px;"><a href="{href}" '
                f'style="color:{BLUE};text-decoration:none;">{e(right)}</a></td></tr>')

    out.append(
        f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        f'style="margin:14px 0 0;border-top:1px solid {SURF};">'
        + row(c["reply"], REPLY_TO, f"mailto:{REPLY_TO}")
        + row(c["threads"], f"@{THREADS_HANDLE} →", THREADS_URL)
        + row(c["instagram"], f"@{INSTAGRAM_HANDLE} →", INSTAGRAM_DM_URL)
        + "</table>")
    if variant == "hello":
        out += [p(c["notice"][0], top=30), p(c["notice"][1])]
        out.append(f'<p style="margin:16px 0 0;"><a href="{APP_STORE_URL}" style="display:inline-block;'
                   f'border:1px solid {INK};color:{INK};text-decoration:none;font-size:14px;font-weight:600;'
                   f'padding:9px 16px;border-radius:999px;">{e(c["update_cta"])}</a></p>')
    out += [p(c["close"], top=30), p(c["sign"], top=22)]
    return "".join(out)


def html_body(lang: str, variant: str) -> str:
    langs = ["ko", "en"] if lang == "both" else [lang]
    divider = f'<div style="margin:40px 0 34px;border-top:1px solid {SURF};"></div>'
    body = divider.join(section_html(COPY[l], variant) for l in langs)
    foot = " ".join(dict.fromkeys(COPY[l]["foot"][variant] for l in langs))
    return f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>{FONT_FACE}</style></head><body style="margin:0;background:{PAPER};">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{PAPER};padding:40px 20px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;"><tr><td style="font-family:{FONT};color:{INK};">
<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 30px;"><tr>
<td style="vertical-align:middle;padding-right:14px;"><a href="{SITE_URL}"><img src="{LOGO_URL}" width="52" height="52" alt="nawana" style="display:block;width:52px;height:52px;border-radius:13px;"></a></td>
<td style="vertical-align:middle;"><div style="font-size:21px;font-weight:700;">nawana</div><div style="font-size:12px;color:{FAINT};margin-top:3px;font-family:{MONO};">Learn a language from your fluent self.</div></td>
</tr></table>
{body}
<div style="margin-top:40px;padding-top:18px;border-top:1px solid {SURF};font-size:12px;line-height:1.7;color:{FAINT};">
<a href="{SITE_URL}" style="color:{FAINT};text-decoration:none;">nawana.app</a> &nbsp;·&nbsp;
<a href="{APP_STORE_URL}" style="color:{FAINT};text-decoration:none;">App Store</a> &nbsp;·&nbsp;
<a href="mailto:{REPLY_TO}" style="color:{FAINT};text-decoration:none;">{REPLY_TO}</a><br>Dear RoRo · Munich<br>{e(foot)}</div>
</td></tr></table></td></tr></table></body></html>"""


def text_body(lang: str, variant: str) -> str:
    parts = []
    for l in (["ko", "en"] if lang == "both" else [lang]):
        c = COPY[l]
        s = [c["hi"], c["thanks"][variant], f"[{c['story_h']}]", *c["story"]]
        if variant == "signup":
            s += [f"[{c['first_h']}]", c["first"]]
        s += [f"[{c['comm_tag']}] {COMMUNITY_URL}", c["comm_intro"],
              "\n".join(f"- {h}: {t}" for h, t in c["comm_items"]),
              f"[{c['reach_h']}]", c["reach"],
              f"{c['reply']}: {REPLY_TO}\n{c['threads']}: {THREADS_URL}\n{c['instagram']}: {INSTAGRAM_DM_URL}",
              *( [*c["notice"], f"{c['update_cta']}: {APP_STORE_URL}"] if variant == "hello" else []),
              c["close"], c["sign"], c["foot"][variant]]
        parts.append("\n\n".join(s))
    return "\n\n· · ·\n\n".join(parts)


def subject(lang: str, variant: str) -> str:
    return BOTH_SUBJECT[variant] if lang == "both" else COPY[lang]["subject"][variant]


def sender(lang: str) -> str:
    return COPY["ko" if lang == "both" else lang]["from"]


# --------------------------------------------------------------------------
# Plumbing.
# --------------------------------------------------------------------------

def keychain(service: str) -> str | None:
    r = subprocess.run(["security", "find-generic-password", "-s", service, "-w"], capture_output=True, text=True)
    raw = r.stdout.strip() if r.returncode == 0 else ""
    if raw.startswith("go-keyring-base64:"):
        raw = base64.b64decode(raw[len("go-keyring-base64:"):]).decode()
    return raw or None


_TOKEN = None


def sql(query: str) -> list[dict]:
    global _TOKEN
    _TOKEN = _TOKEN or keychain("Supabase CLI") or sys.exit("run `supabase login` first")
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{SUPABASE_PROJECT_REF}/database/query",
        data=json.dumps({"query": query}).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {_TOKEN}")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def q(s) -> str:
    return "null" if s is None else "'" + str(s).replace("'", "''") + "'"


def send(key: str, to: str, lang: str, variant: str, idem: str) -> str:
    payload = {
        "from": sender(lang), "to": [to], "reply_to": REPLY_TO,
        "subject": subject(lang, variant),
        "html": html_body(lang, variant), "text": text_body(lang, variant),
        "headers": {"List-Unsubscribe": f"<mailto:{REPLY_TO}?subject=unsubscribe>", "X-Entity-Ref-ID": idem},
        "tags": [{"name": "campaign", "value": f"welcome-{variant}"}, {"name": "lang", "value": lang}],
    }
    req = urllib.request.Request("https://api.resend.com/emails", data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Idempotency-Key", idem)
    req.add_header("User-Agent", "futurevoice-setup/1.0")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as err:
        raise RuntimeError(f"{err.code} {err.read().decode()[:300]}") from None


RECIPIENTS_SQL = """
select u.id::text as user_id, u.email,
       case when p.setup_at is null then 'both'
            when p.native_language = 'ko' then 'ko' else 'en' end as lang,
       w.sent_at
  from auth.users u
  left join profiles p on p.id = u.id
  left join welcome_mails w on w.user_id = u.id
 where not u.is_anonymous and u.email is not null and u.deleted_at is null
 order by u.created_at
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="DIR")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--send", action="store_true")
    ap.add_argument("--test", metavar="EMAIL")
    ap.add_argument("--lang", default="both", choices=["ko", "en", "both"])
    ap.add_argument("--variant", default="hello", choices=["hello", "signup"])
    ap.add_argument("--limit", type=int)
    a = ap.parse_args()

    if a.preview:
        os.makedirs(a.preview, exist_ok=True)
        for v in ("signup", "hello"):
            for l in ("ko", "en", "both"):
                path = os.path.join(a.preview, f"welcome-{v}-{l}.html")
                open(path, "w").write(html_body(l, v))
                print(path, "·", subject(l, v))
        return

    key = None
    if a.test:
        key = os.environ.get("RESEND_API_KEY") or keychain("Resend nawana")
        print("sent", send(key, a.test, a.lang, a.variant, f"welcome-test-{a.variant}-{a.lang}-{int(time.time())}"))
        return

    rows = [r for r in sql(RECIPIENTS_SQL) if r["user_id"] not in TEST_IDS]
    pending = [r for r in rows if not r["sent_at"]]
    by = {}
    for r in pending:
        by[r["lang"]] = by.get(r["lang"], 0) + 1
    relay = sum(1 for r in pending if r["email"].endswith("@privaterelay.appleid.com"))
    print(f"{len(rows)} accounts, {len(rows) - len(pending)} already mailed, {len(pending)} pending "
          f"({', '.join(f'{k} {v}' for k, v in sorted(by.items()))}; {relay} via Apple relay)")
    if a.limit:
        pending = pending[:a.limit]
    if not a.send:
        for r in pending:
            print(f"  {r['lang']:4} {r['email']}")
        print("dry run: nothing sent. --send to deliver.")
        return

    key = os.environ.get("RESEND_API_KEY") or keychain("Resend nawana") or sys.exit("no Resend key")
    ok = fail = 0
    for r in pending:
        sql(f"insert into welcome_mails (user_id, email, lang, variant) values "
            f"({q(r['user_id'])}, {q(r['email'])}, {q(r['lang'])}, 'hello') on conflict (user_id) do nothing")
        try:
            rid = send(key, r["email"], r["lang"], "hello", f"welcome-hello-{r['user_id']}")
            sql(f"update welcome_mails set sent_at = now(), resend_id = {q(rid)}, error = null "
                f"where user_id = {q(r['user_id'])}")
            ok += 1
            print(f"  sent {r['lang']:4} {r['email']}")
        except Exception as err:
            sql(f"update welcome_mails set error = {q(str(err)[:300])} where user_id = {q(r['user_id'])}")
            fail += 1
            print(f"  FAIL {r['email']}: {err}")
        time.sleep(PER_SEND_PAUSE)
    print(f"done: {ok} sent, {fail} failed")


if __name__ == "__main__":
    main()
