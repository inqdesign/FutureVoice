#!/usr/bin/env python3
"""Read the Find-people introduction the app would actually publish.

The paragraph a stranger's phone speaks as "you" is written by one Gemini
call (`PublicIntroComposer`), and the only way to judge it is to read one —
the same argument `voice-remix-probe.sh` rests on: tune it by reading the
output, never by feel. This runs the REAL prompt, extracted from
`PublicIntroComposer.swift` so it can never drift from the app, through the
REAL edge function, on a profile you hand it as JSON.

  ./scripts/public-intro-probe.py [profile.json] [--language en]

With no file it uses the sample profile below, which is deliberately the
messy kind: episode lines, two languages, a news line. It prints what the
pre-2026-09-25 build would have published (the concatenation) and then what
the composer writes, so the two can be read side by side.

Auth: the dev account in ~/keys/nawana-dev-account.txt (email on line 1,
password on line 2), signed in against the SUPABASE_URL in
Config/FutureVoice.xcconfig. Nothing is written anywhere — the call is free
(`purpose: "public-intro"`) and the result is not saved to any profile.
"""

import argparse
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMPOSER = ROOT / "FutureVoice/Services/PublicIntroComposer.swift"
COACHING = ROOT / "FutureVoice/Services/CoachingLanguage.swift"
XCCONFIG = ROOT / "Config/FutureVoice.xcconfig"
ACCOUNT = pathlib.Path.home() / "keys/nawana-dev-account.txt"

# A profile shaped like a real one that has been talked to for a few weeks:
# the typed fields, then remembered lines at the rung the learner set. Only
# `fact` lines that a stranger may hear reach the prompt.
SAMPLE = {
    "name": "Eunggyu",
    "occupation": "Solo founder, building apps.\nIm building nawana: learn a language from your fluent self.",
    "city": "Munich",
    "country": "Germany",
    "stay": "15 years",
    "interests": [],
    "situations": [
        "Work meetings", "Client calls", "Doctor / clinic", "Kita / school",
        "Travel", "Online shopping", "Streaming / shows", "Reading articles",
        "Daily small talk",
    ],
    "facts": [
        "Launching an app in a day or two.",
        "Building in public by sharing progress and passion online.",
        "Transitioned career to become a solo founder.",
        "Gained a new app user from Hong Kong who is learning Korean.",
        "Debugging a Bluetooth connectivity issue in car for Nawana app.",
        "Studied English abroad in Portsmouth, England as a student.",
        "앱의 일본어 버전을 출시함",
        "영국 3년, 독일 16년 등 총 19년간 해외 거주 경험이 있다.",
        "Posted on Threads targeting Koreans in Germany and gained 20 new users.",
        "converted a trial user to a subscription",
        "building a weekly testing feature for Nawana",
        "Testing Nawana app by acting as a beginner foreign user.",
    ],
    # Shown only to prove they are dropped: a `now` line and a locked one
    # never reach the prompt, because `strangerFacts` never yields them.
    "excluded_now_lines": ["아이의 한글학교 등교를 위해 이동 중이었다."],
}

LANGUAGE_NAMES = {"en": "English", "de": "German", "ko": "Korean",
                  "ja": "Japanese", "es": "Spanish", "fr": "French"}


def swift_multiline(source: str, start: int) -> str:
    """The Swift multiline literal beginning at `start` (the opening \"\"\")."""
    body_start = source.index("\n", start) + 1
    end = source.index('"""', body_start)
    closing_indent = len(source[:end].rsplit("\n", 1)[1])
    lines = source[body_start:end].rstrip().split("\n")
    out = []
    for line in lines:
        out.append(line[closing_indent:] if line[:closing_indent].isspace() or not line.strip() else line.lstrip())
    text = "\n".join(out)
    # A backslash at end of line is a Swift line continuation: the newline
    # goes, the space before the backslash stays, so the join adds nothing.
    return re.sub(r" ?\\\n\s*", " ", text)


def breath_rule() -> str:
    src = COACHING.read_text(encoding="utf-8")
    i = src.index("static let breathPunctuation = \"\"\"")
    return swift_multiline(src, src.index('"""', i))


def build_prompt(p: dict, language: str) -> str:
    """The app's own prompt, read out of the Swift source."""
    src = COMPOSER.read_text(encoding="utf-8")
    i = src.index("static func prompt(")
    template = swift_multiline(src, src.index('return """', i) + len("return "))
    language_name = LANGUAGE_NAMES.get(language, language)

    about = []
    if p.get("name"):
        about.append(f"- Name: {p['name']}")
    place = ", ".join(x for x in [p.get("city", ""), p.get("country", "")] if x)
    if place:
        stay = f" ({p['stay']})" if p.get("stay") else ""
        about.append(f"- Lives in: {place}{stay}")
    if p.get("occupation"):
        about.append(f"- Does: {p['occupation']}")
    if p.get("interests"):
        about.append(f"- Interests: {', '.join(p['interests'])}")
    if p.get("situations"):
        about.append(f"- Uses {language_name} for: {', '.join(p['situations'])}")
    if p.get("facts"):
        about.append("- Things they've said about their life (each is a plain fact, or an OUTLINE they chose to keep vague):")
        about += [f"  · {f}" for f in p["facts"]]

    return (template
            .replace("\\(about.joined(separator: \"\\n\"))", "\n".join(about))
            .replace("\\(CoachingLanguage.breathPunctuation)", breath_rule())
            .replace("\\(languageName)", language_name))


def fallback(p: dict) -> str:
    """What the pre-2026-09-25 build published: the concatenation."""
    parts = []
    if p.get("occupation"):
        parts.append(p["occupation"])
    if p.get("stay") and p.get("city"):
        parts.append(f"{p['city']} · {p['stay']}")
    if p.get("situations"):
        parts.append(", ".join(p["situations"]))
    parts += p.get("facts", [])
    return "\n".join(parts)


def config() -> tuple[str, str]:
    values = {}
    for line in XCCONFIG.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.strip().startswith("//"):
            k, v = line.split("=", 1)
            values[k.strip()] = v.strip()
    url, key = values.get("SUPABASE_URL", ""), values.get("SUPABASE_ANON_KEY", "")
    # The xcconfig escapes // as $(SLASH)$(SLASH) — Xcode reads // as a comment.
    url = url.replace("$(SLASH)", "/")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_ANON_KEY missing from Config/FutureVoice.xcconfig")
    return url, key


def post(url: str, body: dict, headers: dict) -> dict:
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", **headers})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"{url} → HTTP {e.code}: {e.read().decode()[:400]}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("profile", nargs="?", help="JSON file shaped like SAMPLE")
    ap.add_argument("--language", default="en", help="target language code")
    ap.add_argument("--prompt-only", action="store_true", help="print the prompt, call nothing")
    args = ap.parse_args()

    p = json.loads(pathlib.Path(args.profile).read_text(encoding="utf-8")) if args.profile else SAMPLE
    prompt = build_prompt(p, args.language)

    if args.prompt_only:
        print(prompt)
        return

    print("=" * 72)
    print("BEFORE — what the concatenation published")
    print("=" * 72)
    print(fallback(p))
    if p.get("excluded_now_lines"):
        print("\n(never reaches the prompt — news, not who you are: "
              + "; ".join(p["excluded_now_lines"]) + ")")

    base, anon = config()
    email, password = ACCOUNT.read_text(encoding="utf-8").split()[:2]
    auth = post(f"{base}/auth/v1/token?grant_type=password",
                {"email": email, "password": password}, {"apikey": anon})

    body = {
        "model": "gemini-3.1-flash-lite",
        "system_instruction": {"parts": [{"text": prompt}]},
        "contents": [{"role": "user", "parts": [{"text": "Write the introduction."}]}],
        "generationConfig": {"maxOutputTokens": 800,
                             "thinkingConfig": {"thinkingLevel": "low"},
                             "responseMimeType": "application/json"},
        "purpose": "public-intro",
    }
    out = post(f"{base}/functions/v1/gemini", body,
               {"Authorization": f"Bearer {auth['access_token']}",
                "X-Idempotency-Key": f"probe-{args.language}-{abs(hash(json.dumps(p, sort_keys=True)))}"})
    text = out["candidates"][0]["content"]["parts"][0]["text"]

    print()
    print("=" * 72)
    print(f"AFTER — what PublicIntroComposer writes ({LANGUAGE_NAMES.get(args.language, args.language)})")
    print("=" * 72)
    try:
        print(json.loads(text)["intro"])
    except Exception:
        print(text)


if __name__ == "__main__":
    main()
