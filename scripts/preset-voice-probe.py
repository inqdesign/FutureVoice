#!/usr/bin/env python3
"""Which ElevenLabs library voices should the counterpart presets be, per
target language? Pick by ear.

The four presets (`VoicePreset.catalog`: Paige, Mark, Emma, James) are
American/British English speakers. Reading Korean, they sound like an
English speaker reading Korean — which is what a Watch scene's barista or a
Find-people stranger then sounds like to every Korean learner. The fix is a
native voice per target language, and the choice is one only ears can make
(same discipline as tts-model-probe.sh / voice-remix-probe.sh).

For one language this asks the ElevenLabs Voice Library for its most-used
conversational voices of each gender, then synthesizes the SAME scene lines
with each — production voice settings, production model (turbo v2.5), the
default speech speed — so the only difference between two files is the
voice. A voice that can't be synthesized directly (library voices sometimes
have to be added to the account first) falls back to its own preview clip,
marked `-preview`, which is in whatever language its owner recorded.

    scripts/preset-voice-probe.py ko            # 6 female + 6 male
    scripts/preset-voice-probe.py ja --per 4
    OUT=~/Desktop/x scripts/preset-voice-probe.py de

Writes <out>/<gender>-<nn>-<name>-<voice_id>-<line>.mp3 and manifest.tsv
(voice id, owner id, accent, age, description, usage). About 2 lines x 12
voices of synthesis, ~1,500 turbo credits for Korean. Run it yourself — the
key is read the way every probe reads it.

LISTEN FOR: does this sound like someone who lives there (not a reader), is
it pleasant for a 3-minute scene, and does it still sound like a PERSON at
0.9 speed. Pick one female + one male (or two of each if the four built-in
characters should all get a native voice) and send back the voice ids.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Counterpart-side lines, the register a scene or a stranger call produces:
# one service line, one casual line with a question (intonation matters).
LINES = {
    "ko": [
        ("service", "주문하신 라떼 나왔습니다. 혹시 시럽 추가하셨던가요? 영수증에는 없는 것 같아서요."),
        ("casual", "아 진짜? 나도 거기 가봤는데, 주말엔 사람이 너무 많더라. 너는 평일에 갔어?"),
    ],
    "ja": [
        ("service", "お待たせしました、ラテです。シロップの追加はございましたか？レシートには載っていないようで。"),
        ("casual", "え、ほんと？私もあそこ行ったことあるけど、週末は混んでたなあ。平日に行ったの？"),
    ],
    "de": [
        ("service", "Ihr Latte, bitte schön. Hatten Sie noch Sirup dazu bestellt? Auf dem Bon sehe ich nichts."),
        ("casual", "Echt jetzt? Da war ich auch mal, aber am Wochenende war's total voll. Warst du unter der Woche da?"),
    ],
    "en": [
        ("service", "Here's your latte. Did you add syrup to that? I don't see it on the receipt."),
        ("casual", "Oh really? I've been there too, but it was packed on the weekend. Did you go on a weekday?"),
    ],
}


def api_key() -> str:
    k = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if k:
        return k
    dv = ROOT / "gateway" / ".dev.vars"
    if dv.exists():
        m = re.search(r"^ELEVENLABS_API_KEY\s*=\s*\"?([^\"\n]+)", dv.read_text(), re.M)
        if m:
            return m.group(1).strip()
    f = Path.home() / "keys" / "elevenlabs.txt"
    if f.exists():
        return f.read_text().strip()
    sys.exit("no ElevenLabs key: set ELEVENLABS_API_KEY or write it to ~/keys/elevenlabs.txt")


def request(url, key, body=None):
    headers = {"xi-api-key": key}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def library(lang, gender, per, key):
    q = urllib.parse.urlencode({
        "page_size": 30, "language": lang, "gender": gender,
        "use_cases": "conversational", "sort": "usage_character_count_1y",
    })
    raw = request(f"https://api.elevenlabs.io/v1/shared-voices?{q}", key)
    voices = json.loads(raw).get("voices", [])
    # Native speakers only: the library tags a voice with the language it
    # was RECORDED in; a multilingual English voice tagged "ko" is exactly
    # the problem this probe exists to replace.
    native = [v for v in voices if (v.get("language") or "").startswith(lang)]
    return (native or voices)[:per]


def slug(s):
    return re.sub(r"[^A-Za-z0-9]+", "_", s or "voice").strip("_")[:24]


def main():
    args = sys.argv[1:]
    if not args or args[0] not in LINES:
        sys.exit(f"usage: {sys.argv[0]} <{'|'.join(LINES)}> [--per N]")
    lang = args[0]
    per = int(args[args.index("--per") + 1]) if "--per" in args else 6
    speed = float(os.environ.get("SPEED", "0.9"))
    key = api_key()
    out = Path(os.environ.get("OUT") or
               Path.home() / "Desktop" / "beta audio" / f"preset-voice-probe-{lang}")
    out.mkdir(parents=True, exist_ok=True)

    manifest = out / "manifest.tsv"
    rows = ["gender\tn\tname\tvoice_id\towner_id\taccent\tage\tdescriptive\tusage_1y\tfiles\tdescription"]
    # Production voice settings — supabase/functions/elevenlabs-tts/index.ts.
    settings = {"stability": 0.55, "similarity_boost": 0.90, "style": 0,
                "use_speaker_boost": True, "speed": speed}

    for gender in ("female", "male"):
        voices = library(lang, gender, per, key)
        print(f"{gender}: {len(voices)} voices", file=sys.stderr)
        for n, v in enumerate(voices, 1):
            vid, name = v["voice_id"], v.get("name", "")
            stem = f"{gender}-{n:02d}-{slug(name)}-{vid}"
            files = []
            for label, text in LINES[lang]:
                f = out / f"{stem}-{label}.mp3"
                try:
                    f.write_bytes(request(
                        f"https://api.elevenlabs.io/v1/text-to-speech/{vid}", key,
                        {"text": text, "model_id": "eleven_turbo_v2_5",
                         "voice_settings": settings}))
                    files.append(f.name)
                except urllib.error.HTTPError as e:
                    print(f"  ! {name} ({vid}) {label}: HTTP {e.code} "
                          f"{e.read()[:160]!r}", file=sys.stderr)
                    break
            if not files and v.get("preview_url"):
                f = out / f"{stem}-preview.mp3"
                f.write_bytes(urllib.request.urlopen(v["preview_url"], timeout=60).read())
                files.append(f.name)
            print(f"  {n:02d} {name}  {v.get('accent','')}  {v.get('age','')}  "
                  f"{v.get('descriptive','')}  → {len(files)} file(s)", file=sys.stderr)
            desc = (v.get("description") or "").replace("\t", " ").replace("\n", " ")
            rows.append("\t".join(str(x) for x in (
                gender, n, name, vid, v.get("public_owner_id", ""), v.get("accent", ""),
                v.get("age", ""), v.get("descriptive", ""),
                v.get("usage_character_count_1y", ""), ",".join(files), desc)))

    manifest.write_text("\n".join(rows) + "\n")
    print(f"\n  open \"{out}\"", file=sys.stderr)


if __name__ == "__main__":
    main()
