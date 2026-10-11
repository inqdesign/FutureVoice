#!/usr/bin/env python3
# Does shadow scoring CATCH what the learner got wrong? (ko · ja · en · de)
#
# Synthesizes "attempts" — the target line said right, and said with one
# deliberate slip (a dropped word, a wrong particle or ending, a sound slip) —
# in a native Korean voice and in an English voice reading Korean (a learner's
# accent), runs each through the LIVE audio-grounded transcribe prompt
# (extracted from ShadowTranscriber.swift so it cannot drift) on the same
# model and thinking level, then scores it with a port of ShadowEngine's
# Korean score (syllable alignment, eojeol credit). A slip is CAUGHT when
# the score drops below the clean take.
#
# Keys: gateway/.dev.vars (GEMINI_API_KEY, ELEVENLABS_API_KEY) or
# ~/keys/elevenlabs.txt. ~2 × len(CASES) syntheses + as many Gemini calls.
#   scripts/shadow-probe.py <ko|ja|en|de> [out_dir]
# Scoring ported: word diff for en/de, syllable alignment + eojeol credit for
# ko, CHARACTER diff for ja (the probe has no segmenter — ja's word credit is
# pinned by ShadowEngineTests instead).
import base64, io, json, os, re, sys, urllib.request, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANG = sys.argv[1] if len(sys.argv) > 1 else "ko"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser(f"~/Desktop/beta audio/shadow-probe/{LANG}")
os.makedirs(OUT, exist_ok=True)

env = {}
p = os.path.join(ROOT, "gateway/.dev.vars")
if os.path.exists(p):
    env = {k.strip(): v.strip().strip('"') for k, v in (l.split("=", 1) for l in open(p) if "=" in l)}
GKEY = env["GEMINI_API_KEY"]
EKEY = os.environ.get("ELEVENLABS_API_KEY") or env.get("ELEVENLABS_API_KEY") or \
    open(os.path.expanduser("~/keys/elevenlabs.txt")).read().strip()

src = open(os.path.join(ROOT, "FutureVoice/Services/ShadowTranscriber.swift")).read()
body = re.search(r'private static func prompt\(targetLanguage: String\) -> String \{.*?return """\n(.*?)\n\s*"""', src, re.S).group(1)
PROMPT = "\n".join(l[8:] if l.startswith("        ") else l for l in body.split("\n")).replace("\\(target)", {"ko": "Korean", "ja": "Japanese", "en": "English", "de": "German"}[LANG]) + os.environ.get("EXTRA", "")

# "native" speaks the language natively where the account has such a voice;
# "accent" is a speaker of ANOTHER language reading it — a learner's accent.
KO_VOICE, EN_VOICE = "5n5gqmaQi9Ewevrz7bOS", "NDTYOmYEjbDIVCKB35i3"
VOICES = {"ko": {"native": KO_VOICE, "accent": EN_VOICE},
          "ja": {"ko-voice": KO_VOICE, "en-voice": EN_VOICE},
          "en": {"native": EN_VOICE, "accent": KO_VOICE},
          "de": {"en-voice": EN_VOICE, "ko-voice": KO_VOICE}}[LANG]

# (target, what is actually said, kind)
KO = [
    ("어제 친구랑 같이 영화를 봤어요.", None, "clean"),
    ("어제 친구랑 같이 영화를 봤어요.", "어제 친구랑 영화를 봤어요.", "drop word"),
    ("어제 친구랑 같이 영화를 봤어요.", "어제 친구랑 같이 영화가 봤어요.", "particle"),
    ("어제 친구랑 같이 영화를 봤어요.", "어제 친구랑 같이 영화를 봐요.", "tense"),
    ("주말에 시간 있으면 커피 한잔 할래?", None, "clean"),
    ("주말에 시간 있으면 커피 한잔 할래?", "주말에 시간 있으면 코피 한잔 할래?", "vowel 어→오"),
    ("주말에 시간 있으면 커피 한잔 할래?", "주말에 시간 있으면 커피 한잔 할래요?", "ending"),
    ("불고기가 정말 맛있었어요.", None, "clean"),
    ("불고기가 정말 맛있었어요.", "풀고기가 정말 맛있었어요.", "lax→aspirated"),
    ("불고기가 정말 맛있었어요.", "불고기가 정말 마시서요.", "syllable dropped"),
    ("학교 끝나고 도서관에 갈 거야.", None, "clean"),
    ("학교 끝나고 도서관에 갈 거야.", "하교 끝나고 도서관에 갈 거야.", "batchim dropped"),
    ("학교 끝나고 도서관에 갈 거야.", "학교 끝나고 도서관에서 갈 거야.", "particle"),
    ("요즘 일이 너무 많아서 좀 피곤해.", None, "clean"),
    ("요즘 일이 너무 많아서 좀 피곤해.", "요즘 일이 너무 많아서 피곤해.", "drop word"),
    ("요즘 일이 너무 많아서 좀 피곤해.", "요즘 일이 너무 마나서 좀 비곤해.", "sound slips"),
]
JA = [
    ("昨日友達と映画を見ました。", None, "clean"),
    ("昨日友達と映画を見ました。", "昨日映画を見ました。", "drop word"),
    ("昨日友達と映画を見ました。", "昨日友達と映画が見ました。", "particle"),
    ("昨日友達と映画を見ました。", "昨日友達と映画を見ます。", "tense"),
    ("昨日友達と映画を見ました。", "昨日ともだちとえがを見ました。", "long vowel えい→え"),
    ("週末に時間があったらコーヒーでも飲もう。", None, "clean"),
    ("週末に時間があったらコーヒーでも飲もう。", "週末に時間があったらコーヒー飲もう。", "drop word"),
    ("週末に時間があったらコーヒーでも飲もう。", "週末に時間があたらコヒでも飲もう。", "sokuon + long vowel"),
    ("ちょっと待ってください。", None, "clean"),
    ("ちょっと待ってください。", "ちょと まてください。", "sokuon dropped"),
]
EN = [
    ("We walked to the park yesterday.", None, "clean"),
    ("We walked to the park yesterday.", "We walk to the park yesterday.", "-ed dropped"),
    ("We walked to the park yesterday.", "We walked to park yesterday.", "article dropped"),
    ("She likes coffee in the morning.", None, "clean"),
    ("She likes coffee in the morning.", "She like coffee in the morning.", "-s dropped"),
    ("She likes coffee in the morning.", "She likes coffee at the morning.", "preposition"),
    ("I think we should leave early.", None, "clean"),
    ("I think we should leave early.", "I sink we should leave early.", "th→s"),
    ("I think we should leave early.", "I think we should live early.", "vowel ee→i"),
    ("I bought a new car last week.", None, "clean"),
    ("I bought a new car last week.", "I buyed a new car last week.", "irregular past"),
]
DE = [
    ("Ich habe gestern einen Film gesehen.", None, "clean"),
    ("Ich habe gestern einen Film gesehen.", "Ich habe gestern ein Film gesehen.", "article case"),
    ("Ich habe gestern einen Film gesehen.", "Ich habe einen Film gesehen.", "drop word"),
    ("Ich bin gestern ins Kino gegangen.", None, "clean"),
    ("Ich bin gestern ins Kino gegangen.", "Ich habe gestern ins Kino gegangen.", "auxiliary"),
    ("Das Wetter ist heute sehr schön.", None, "clean"),
    ("Das Wetter ist heute sehr schön.", "Das Wetter ist heute sehr schon.", "umlaut ö→o"),
    ("Die Bücher liegen auf dem Tisch.", None, "clean"),
    ("Die Bücher liegen auf dem Tisch.", "Die Bucher liegen auf dem Tisch.", "umlaut ü→u"),
    ("Die Bücher liegen auf dem Tisch.", "Die Bücher liegen auf den Tisch.", "dative"),
]
CASES = {"ko": KO, "ja": JA, "en": EN, "de": DE}[LANG]


def synth(text, voice):
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=pcm_16000",
        data=json.dumps({"text": text, "model_id": "eleven_turbo_v2_5", "language_code": LANG,
                         "voice_settings": {"stability": 0.55, "similarity_boost": 0.9, "style": 0,
                                            "use_speaker_boost": True}}).encode(),
        headers={"xi-api-key": EKEY, "Content-Type": "application/json"})
    pcm = urllib.request.urlopen(req, timeout=60).read()
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(pcm)
    return buf.getvalue()


def transcribe(wav):
    body = {
        "systemInstruction": {"parts": [{"text": PROMPT}]},
        "contents": [{"role": "user", "parts": [
            {"text": "Transcribe the attached audio."},
            {"inlineData": {"mimeType": "audio/wav", "data": base64.b64encode(wav).decode()}}]}],
        "generationConfig": {"maxOutputTokens": 1024, "responseMimeType": "application/json",
                             "thinkingConfig": {"thinkingLevel": os.environ.get("THINKING", "minimal")}},
    }
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={GKEY}",
        data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=60))
    text = "".join(p.get("text", "") for p in r["candidates"][0]["content"]["parts"])
    try:
        return json.loads(text).get("transcript") or ""
    except Exception:
        return "<<" + text + ">>"


def tokens(s):  # ShadowEngine.tokenize, .syllable
    return [c for w in re.split(r"[^\w'\-]+", s.lower()) if w for c in w]


def score(target, heard):
    if LANG in ("en", "de"):
        a = [w for w in re.split(r"[^\w'\-]+", target.lower()) if w]
        b = [w for w in re.split(r"[^\w'\-]+", heard.lower()) if w]
        return plain(a, b)
    if LANG == "ja":
        return plain(tokens(target), tokens(heard))
    return korean(target, heard)


def plain(a, b):  # ShadowEngine.analyze: matches / max(n, m), sqrt curve
    n, m = len(a), len(b)
    dp = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1): dp[i][0] = i
    for j in range(m + 1): dp[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            dp[i][j] = dp[i-1][j-1] if a[i-1] == b[j-1] else 1 + min(dp[i-1][j-1], dp[i-1][j], dp[i][j-1])
    i, j, match = n, m, 0
    while i > 0 and j > 0:
        if a[i-1] == b[j-1]: match += 1; i -= 1; j -= 1
        elif dp[i][j] == dp[i-1][j-1] + 1: i -= 1; j -= 1
        elif dp[i][j] == dp[i-1][j] + 1: i -= 1
        else: j -= 1
    d = max(n, m)
    return round((match / d) ** 0.5 * 100) if d else 0


def korean(target, heard):
    a, b = tokens(target), tokens(heard)
    n, m = len(a), len(b)
    dp = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1): dp[i][0] = i
    for j in range(m + 1): dp[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            dp[i][j] = dp[i-1][j-1] if a[i-1] == b[j-1] else 1 + min(dp[i-1][j-1], dp[i-1][j], dp[i][j-1])
    # ShadowEngine.koreanWordRatio: a target eojeol counts only when every
    # syllable in it matched; extra speech converts at syllables per word.
    ops, i, j = [], n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and a[i-1] == b[j-1]: ops.append("m"); i -= 1; j -= 1
        elif i > 0 and j > 0 and dp[i][j] == dp[i-1][j-1] + 1: ops.append("s"); i -= 1; j -= 1
        elif i > 0 and (j == 0 or dp[i][j] == dp[i-1][j] + 1): ops.append("d"); i -= 1
        else: j -= 1
    ops.reverse()
    spans, c = [], 0
    for w in target.split():
        k = len(tokens(w))
        if k: spans.append(range(c, c + k))
        c += k
    if not spans or not n: return 0
    ok = sum(all(ops[x] == "m" for x in sp) for sp in spans)
    denom = max(len(spans), m / (n / len(spans)))
    return round((ok / denom) ** 0.5 * 100)


rows = []
for vname, vid in VOICES.items():
    for k, (target, said, kind) in enumerate(CASES):
        said = said or target
        wav = synth(said, vid)
        open(os.path.join(OUT, f"{vname}-{k:02d}.wav"), "wb").write(wav)
        heard = transcribe(wav)
        s = score(target, heard)
        exact = tokens(heard) == tokens(said) if LANG != "en" and LANG != "de" else re.sub(r"[^\w\s]", "", heard.lower()).split() == re.sub(r"[^\w\s]", "", said.lower()).split()
        rows.append((vname, kind, target, said, heard, s, exact))
        print(f"{vname:8} {kind:20} score {s:3}  {'=said' if exact else '≠said'}  said「{said}」 heard「{heard}」", flush=True)

json.dump(rows, open(os.path.join(OUT, "results.json"), "w"), ensure_ascii=False, indent=1)
for v in VOICES:
    slips = [r for r in rows if r[0] == v and r[1] != "clean"]
    clean = [r for r in rows if r[0] == v and r[1] == "clean"]
    print(f"\n{v}: clean takes avg {sum(r[5] for r in clean)/len(clean):.0f}, "
          f"slips heard as said {sum(r[6] for r in slips)}/{len(slips)}, "
          f"slips avg score {sum(r[5] for r in slips)/len(slips):.0f}")
