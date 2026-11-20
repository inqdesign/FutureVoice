#!/usr/bin/env python3
"""The same founder letter, in English, to learners whose native language isn't Korean (2026-11-19).

Same audience rules and priority as hesitating-subscribers-web-mail.py (no live
or past Apple subscription, no creators, no test accounts, 5+ min of talk or
opened lately), with native_language <> 'ko'. Its own campaign and sent log.
The link is the English page, the one that shows the web price to everyone.

  python3 scripts/hesitating-subscribers-web-mail-en.py                  # who + dry run
  python3 scripts/hesitating-subscribers-web-mail-en.py --preview out.html
  python3 scripts/hesitating-subscribers-web-mail-en.py --send
"""

import importlib.util
import os

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "hesitating_ko", os.path.join(_here, "hesitating-subscribers-web-mail.py"))
M = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(M)

M.CAMPAIGN = "hesitating-web-discount-en-2026-11-19"
M.SENT_LOG = os.path.join(_here, "..", "build-capture", f"{M.CAMPAIGN}.sent.txt")
M.WEB_URL = WEB_URL = "https://nawana.app/#pricing"
M.ALREADY_SENT = set()

_recipients = M.recipients
M.recipients = lambda min_seconds: _recipients(min_seconds, native="other")

M.SUBJECT = "A note from Eunggyu, who makes nawana"

M.BLOCKS = [
    "Hi, I'm Eunggyu. I'm the one building nawana.",
    "I've been wondering how to reach those of you who tried nawana\n"
    "and are still deciding whether to subscribe, so I'm writing to you myself.",
    "There's still a lot to improve. Even so, I'm confident nawana will feel better\n"
    "than any other AI speaking app you've tried. And I'll keep working on it\n"
    "until I can say that without a second thought.",
    "To be honest, nawana is expensive to run.\n"
    "I'd love to give more of it away for free,\n"
    "but if I did, I couldn't keep it going.\n"
    "For now, everything goes back into making it as good as it can be,\n"
    "even if nothing is left over.",
    "So here's one small thing I can offer.\n"
    "If you subscribe on our website, it's 10% cheaper.\n"
    "Paying on the web skips the app store's fee,\n"
    "and I'd rather pass that saving on to you.",
    ("buttons", [("Subscribe on the web, 10% off", WEB_URL, True)]),
    "Sign in on the website with the same account you use in the app (Apple or Google),\n"
    "and your subscription shows up in the app right away.",
    "If you're not ready to subscribe but would like to support nawana,\n"
    "a rating on the App Store or Google Play would mean a lot.\n"
    "And when you come across my posts, a like or a comment instead of scrolling past\n"
    "helps more people find nawana.",
    ("buttons", [("Rate on the App Store", M.APP_STORE_REVIEW, False),
                 ("Rate on Google Play", M.PLAY_STORE, False)]),
    "This is my first business, and I still have a lot to learn.\n"
    "But I have one goal: that your language actually gets better.\n"
    "And I think the measure of that is the time you spend with nawana open.",
    "When you're on your own, on your commute, in the spare minutes of your day,\n"
    "I want nawana to be what you open instead of social media.\n"
    "I want it to earn a spot on your home screen.\n"
    "I want it to be the language app that suits you best.\n"
    "I promise to put every day I have into that.",
    "It's been two months since I started nawana.\n"
    "Some days I get impatient, and some days the future feels uncertain.\n"
    "What keeps me going is the new people who join every day,\n"
    "and everyone who trusted me enough to subscribe.",
    "Some of you have been working on a language for years, even decades.\n"
    "I'd really love for us to get there together.\n"
    "I hope that a few months from now, you sound a little more like the fluent you.",
    "Eunggyu",
    "P.S. If it's been a while, please update the app before you try it again.\n"
    "P.S. If you'd like to keep using nawana but something is holding you back,\n"
    "just reply to this email and tell me.",
]

M.UNSUB = "If you'd rather not get emails like this, just reply and let me know."

if __name__ == "__main__":
    M.main()
