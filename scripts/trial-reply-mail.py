#!/usr/bin/env python3
"""The founder's reply to meehoo4u's letter (2026-09-26).

2bda6067 wrote on 09-25 after the 30-minute top-up (see
trial-cancelled-mail.py): the trial pool surprised her, she cancelled and
re-subscribed, and she asks three things — how to move to Plus at renewal,
how long the trial's talk time is, and whether a clone of her own voice
understands her pronunciation too kindly. The body below is the founder's
own text, typos and spacing only.

Same rule as every founder mail: dry run by default, `--send` only after the
copy is approved in that turn.
"""

import html
import importlib.util
import json
import os
import sys
import urllib.error
import urllib.request

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "launch_mail", os.path.join(_here, "waitlist-launch-mail.py"))
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)

CAMPAIGN = "trial-reply-2026-09-26"
# Her own mail is a reply to the 09-25 note, so the same subject keeps the
# exchange in one thread on her side.
SUBJECT = "Re: 나와나를 써주셔서 고맙습니다."
USER_ID = "2bda6067-5324-4ad2-ae9b-adbca2592800"
TO = "meehoo4u@gmail.com"

BODY = [
    "안녕하세요.",
    "어제 메일을 받고, 정말 기분이 좋았답니다. "
    "필요한 앱이라고 말씀해주시니 더 바랄 게 없다는 생각과, 제가 가고 있는 방향이 틀리지 않았구나 하는 생각이 듭니다.",
    "좋은 말씀, 또 응원해주셔서 정말 고맙습니다!",
    "질문해주신 것에 대한 답변을 하나씩 드릴게요.",
    # Apple applies an UPGRADE inside a subscription group IMMEDIATELY: the
    # trial ends and Plus is charged the same minute (one intro offer per
    # group, so Plus gets no trial of its own). The server follows at once —
    # DID_CHANGE_RENEWAL_PREF/UPGRADE writes the Plus row, and the app's
    # claimCurrentEntitlements does it again on the next foreground. So the
    # honest answer is "now, not on the 28th", and both routes are offered.
    # She lives in Germany, so the trial's end (2026-09-28 05:59:50 UTC) is
    # said in CEST (UTC+2 until 10-25): the morning of the 28th, ~08:00. The
    # 09-25 note had given her the Korean time, which is 15:00 that day.
    "1. 지금도 앱에서 플러스로 바꾸실 수 있습니다. 프로필 → 구독 → 플러스 플랜 → 요금제 변경을 누르시면 됩니다. "
    "다만 애플에서는 플랜을 올리는 변경이 바로 적용돼서, 지금 누르시면 3일 체험이 그 자리에서 끝나고 플러스 결제가 시작됩니다. "
    "대신 그 순간부터는 체험 없이, 통화 시간 제한 없이 쓰실 수 있어요. "
    "체험을 끝까지 그대로 두고 싶으시면, 체험이 독일 시간으로 9월 28일 아침 8시쯤 끝나니, "
    "그 뒤에 라이트 구독이 시작되면 같은 자리에서 요금제 변경을 하시면 됩니다.",
    "2. 3일 체험 없이, 처음 무료 통화 시간을 10분에서 20분 정도로 늘려서 사용하시고 구독하면, 체험 없이 바로 구독이 되는 방향으로 하려고 합니다. "
    "이전에도 같은 혼란이 있어서, 이 방식이 더 간단하리라 생각이 들어요.",
    "3. 발음 문제는, 잘 알아듣는다는 건 그 단어 단어만을 알아듣기도 하지만 컨텍스트를 이해하고 알아듣는 것이라서, "
    "이건 우리가 사람들과 대화할 때도 마찬가지라고 생각합니다. "
    "발음이 걱정되신다면, 쉐도잉 연습을 더 꾸준하게 많이 반복하시는 걸 추천드립니다. "
    "쉐도잉이 저는 힘들지만 정말 무한 반복 하다 보면, 절대 안 되던 것도 어느덧 되게 되더라고요. 추천드립니다.",
    "4. 목소리 같은 경우에 약간 인도 발음으로 간혹 나오는 경우가 아주 종종 있었습니다. "
    "프로필 → 목소리에서, 다시 녹음하기를 한번 해보시는 걸 추천드립니다. "
    "평상시처럼 최대한 편하게 말씀하시는 게 좋은 결과를 가져오더라고요. 다시 한번 해보시고 피드백을 주세요!",
    "5. 상황은 설명이 조금 부족했던 게 사실입니다. 하지만 써보면 정말 유용한 기능인데요. "
    "제가 기능 하나하나에 대한 설명을 콘텐츠로 만드는 작업을 계획 중입니다. 기대해 주시고요. "
    "추측하신 대로, 상황극이라고 생각하시면 쉽습니다. 유저님께서 영어를 쓰게 될 실제 상황들, "
    "예를 들면 독일에서 병원에 가기 전에 최대한 많은 정보를 주면, 그 상황에 맞는 대화가 만들어지고, "
    "미래의 내가 그 상황에서 나 대신 어떻게 헤쳐나가는지 보는 겁니다. "
    "그걸 통해서 새로운 단어, 표현을 배우고, 연습하면서 내 것으로 만드는 거예요. "
    "그다음 그 상황을 Talk으로 내가 테스트해 보는 거예요. 최대한 배운 내용을 써가면서 말이죠. "
    "상황은 인터뷰, 유치원, 학부모 상담, 마트 등등 셀 수가 없겠죠. 본인이 필요한 어떤 상황도 만드셔도 됩니다.",
    "6. 그것과 연관된 건데 '사람'이라는 게 있답니다. 이건 내가 이미 주변에 매일 독일어를 하는 사람이 있다면, 그 페르소나를 만드는 거예요. "
    "최대한 이 사람에 대해 상세하게 만드는 거죠. 그다음 페르소나와 특정 상황을 배우는 거죠. "
    "실제 유저분 중에 한 분은 국제 부부이신데, 남편을 페르소나로 만들어 놓고, "
    "부부싸움을 할 때 한 번도 시원하게 싸워본 적이 없어서 매번 상황을 만들고, 싸울 준비를 미리 공부하셨다고 하더라고요. "
    "여기에 의사를 만들어도 되고, 주변에 친구들 등등 상황을 미리 보고 아이디어를 얻는다는 게 목적입니다. "
    "물론 그대로 상황이 실제에서 흘러가진 않겠죠. 하지만 맥락을 이해하고, "
    "대화의 흐름이 이런 식으로 흘러가겠구나 이해하고 있으면, 조금 도움이 된답니다.",
    "7. 그리고, 거기서 다른 유저들의 미래의 나를 만날 수도 있습니다. "
    "그냥 거리에서 우연히 사람을 만나서, 아니면 어떤 상황에서 낯선 사람과 이야기를 하게 되듯이요. "
    "그럼 또 새로운 표현들을 공부할 수 있게 되겠죠.",
    "제가 다 답을 드렸는지 모르겠어요.",
    "앞으로 궁금한 것이 있으면 메일로, 스레드 메시지나 인스타그램의 디엠 등 편하신 대로 연락 주세요! "
    "그리고, 이제 2주 된 서비스라 업데이트가 좀 잦을 수 있습니다. 조금씩 더 나아지는구나 하고 이해 부탁드리고요!",
    "제가 유저들의 사용량이나 활동을 보는데, 제가 예상했던 것보다 훨씬 더 잘 사용하시는 것 같아서 너무 좋기도 한 반면, "
    "상세 구독 내용이 추후 변경이 될 수도 있고, 새로운 구독이 추가될 수도 있을 것 같습니다.",
    "미리 말씀을 꼭 드리는 게 맞는 것 같아서 안내드려요! 물론 지금 구독 중이신 내용은 변함이 없다는 점을 알려드려요.",
    "어제 아이 생일 파티 겸 외식을 오랜만에 했는데, 그때 마침 메일을 받았었어요. "
    "너무 기뻤고, 아내에게도 자랑을 했답니다. 바로 답장을 하고 싶었지만, 가족 시간에 집중하느라 답장이 좀 늦었습니다.",
    "좋은 시간을 선물해 주셔서 고맙습니다!",
    "앞으로 지켜봐 주시면, 더 좋은 앱을 만들어서, 이루고자 하시는 그곳에 조금이라도 빨리 가실 수 있도록 잘 만들어 보겠습니다!",
    "좋은 주말 보내세요!",
    "이응규 드림.",
]


def text_body() -> str:
    return "\n\n".join(BODY + [L.SITE_URL])


def html_body() -> str:
    def p(s, top=14):
        return (f'<p style="font-size:16px;line-height:1.7;color:{L.INK};margin:{top}px 0 0;">'
                f'{html.escape(s)}</p>')
    paras = [p(BODY[0], top=0)] + [p(s) for s in BODY[1:]]
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{L.FONT_FACE}</style></head><body style="margin:0;background:{L.PAPER};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{L.PAPER};padding:44px 20px 40px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;">
        <tr><td style="font-family:{L.FONT};color:{L.INK};">
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 30px;">
            <tr>
              <td style="vertical-align:middle;padding-right:14px;">
                <a href="{L.SITE_URL}" style="text-decoration:none;">
                  <img src="{L.LOGO_URL}" width="52" height="52" alt="nawana"
                       style="display:block;width:52px;height:52px;border-radius:13px;">
                </a>
              </td>
              <td style="vertical-align:middle;">
                <div style="font-size:21px;font-weight:700;letter-spacing:-.01em;color:{L.INK};">nawana</div>
                <div style="font-size:12px;color:{L.FAINT};margin-top:3px;font-family:{L.MONO};">{html.escape(L.TAGLINE)}</div>
              </td>
            </tr>
          </table>
          {"".join(paras)}
          <div style="margin-top:40px;padding-top:18px;border-top:1px solid {L.SURF};font-size:12px;line-height:1.7;color:{L.FAINT};">
            <a href="{L.SITE_URL}" style="color:{L.FAINT};text-decoration:none;">nawana.app</a>
            &nbsp;·&nbsp;
            <a href="{L.APP_STORE_URL}" style="color:{L.FAINT};text-decoration:none;">App Store</a>
            &nbsp;·&nbsp;
            <a href="mailto:{L.REPLY_TO}" style="color:{L.FAINT};text-decoration:none;">{L.REPLY_TO}</a>
            <br>{html.escape(L.FOOTER)}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table></body></html>"""


def account() -> dict | None:
    rows = L.sql(f"select email, created_at from auth.users where id = '{USER_ID}'")
    return rows[0] if rows else None


def send(key: str) -> str:
    idem = f"{CAMPAIGN}:{TO}"
    payload = {
        "from": L.FROM, "to": [TO], "reply_to": L.REPLY_TO, "subject": SUBJECT,
        "text": text_body(), "html": html_body(),
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
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["id"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode()[:300]}") from None


def main() -> None:
    # SENT 2026-09-26 (Resend 01a0dcfa-7d2f-70d4-b89f-fd3c7a3b663d). Do not
    # send again; a rerun without --send is a dry run.
    print(f"to: {TO}\nsubject: {SUBJECT}\n")
    print(text_body())
    acct = account()
    print(f"\n--- account {USER_ID[:8]}: {acct}")
    if "--send" not in sys.argv:
        print("dry run. add --send to send.")
        return
    print(f"sent: {send(L.resend_key())}")


if __name__ == "__main__":
    main()
