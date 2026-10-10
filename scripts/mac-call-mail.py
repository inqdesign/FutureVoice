#!/usr/bin/env python3
"""Telling one learner why calls wouldn't open on her Mac (2026-10-10).

7bc59bb6 runs the iPhone app on a MacBookPro18,1. Both calls failed at
audio_start (-10875, 7 and 9 input channels on the built-in mic) before a
byte; shadowing on the same Mac worked. In 60 days no other call hit -10875
or more than 4 input channels. Copy is the founder's (합니다체).

  python3 scripts/mac-call-mail.py            # dry run
  python3 scripts/mac-call-mail.py --send
"""

import importlib.util
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("accent", os.path.join(_here, "accent-apology-mail.py"))
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)
L = A.L

A.CAMPAIGN = "mac-call-2026-10-10"
A.RECIPIENTS = {"7bc59bb6-5a93-46dd-bdbf-c09fb7b56972": ("M", "")}
A.SUBJECT = {"M": "맥에서 통화가 열리지 않았던 이유"}
PARAS = [
    "안녕하세요, 나와나를 만든 이응규입니다.",
    "조금 전 통화를 거셨을 때 연결되지 않고 마이크를 열 수 없다는 오류가 났을 겁니다. "
    "맥북에서 나와나를 쓰실 때 생기는 저희 쪽 문제입니다. 불편을 드려 죄송합니다.",
    "아이폰이나 아이패드에서는 같은 계정으로 바로 통화하실 수 있습니다. "
    "맥에서도 통화가 되도록 고치고 있고, 고쳐지면 다시 알려 드리겠습니다.",
    "궁금하신 점은 이 메일에 답장하시거나 스레드, 인스타그램 DM으로 알려 주세요.",
]
# The accent letter's layout wants five paragraphs (the last under the
# buttons); this one has four, so the fifth is empty and dropped.
A.paragraphs = lambda variant, when: PARAS + [""]
_text, _html = A.text_body, A.html_body
A.text_body = lambda variant, when: _text(variant, when).replace("\n\n\n\n", "\n\n")
A.html_body = lambda variant, when: _html(variant, when).replace(
    '<p style="font-size:16px;line-height:1.65;color:%s;margin:16px 0 0;"></p>' % L.INK, "")

if __name__ == "__main__":
    A.main()
