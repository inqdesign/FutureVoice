#!/usr/bin/env python3
"""One day of the platform's news show, made by hand to be heard by ear.

The show (2026-10-19, founder): every day the PLATFORM picks a handful of
news topics per target language, the same for everyone, and two hosts talk
each one through as a short podcast episode. The platform pays; nothing is
per user. This probe makes one day of it so the hosts, the length and the
voices can be judged before any of it is automated.

    python3 scripts/news-show-probe.py                 # en + de, 5 each
    LANGS=de EPISODES=2 python3 scripts/news-show-probe.py
    OUT_DIR=... python3 scripts/news-show-probe.py

Keys: GEMINI_API_KEY + CARTESIA_API_KEY from gateway/.dev.vars (platform
keys). Writes per language: topics.json, show.json (the manifest the app
reads), one folder per episode with script.json, episode.mp3 (the podcast)
and lines/NNN.mp3 (what the app's player plays). Nothing is uploaded here;
scripts/news-show-publish.sh puts a finished day in R2.
"""
import concurrent.futures as cf
import datetime
import json
import os
import re
import struct
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# A worktree has no .dev.vars (gitignored); DEV_VARS points at the main one.
VARS = dict(l.split("=", 1) for l in open(os.environ.get("DEV_VARS", os.path.join(ROOT, "gateway/.dev.vars")))
            if "=" in l)
GEMINI_KEY = VARS["GEMINI_API_KEY"].strip().strip('"')
CARTESIA_KEY = VARS["CARTESIA_API_KEY"].strip().strip('"')

TODAY = datetime.date.today().isoformat()
LANGS = os.environ.get("LANGS", "en,de").split(",")
EPISODES = int(os.environ.get("EPISODES", "5"))
LEVEL = os.environ.get("LEVEL", "B1")
OUT = os.environ.get("OUT_DIR", os.path.expanduser(f"~/Desktop/beta audio/news-show-{TODAY}"))
MODEL = "gemini-3.6-flash"

# Two hosts per language: the female and male US/German preset slots
# (`VoicePreset.voicedBySlot`), so the show sounds like the app's people.
HOSTS = {
    "en": [("Layla", "999df508-4de5-40a7-8bd3-8c12f678c284"),
           ("Kyle", "c961b81c-a935-4c17-bfb3-ba2239de8c2f")],
    "de": [("Lea", "1ade29fc-6b82-4607-9e70-361720139b12"),
           ("Jonas", "dff81230-ff75-49a4-af44-f6b2f43500d8")],
}
REGION = {"en": "the US and the UK", "de": "Germany, Austria and Switzerland"}
LANG_NAME = {"en": "English", "de": "German"}

SAMPLE_RATE = 44100
SENTENCE_GAP = 0.42   # PacedSpeech's gap between one speaker's sentences
TURN_GAP = 0.55       # a breath longer when the other host takes over
CARTESIA_SPEED = 1.0 + (0.9 - 0.85) / 0.15 * 0.5   # the app's Relaxed rung
USD_PER_CHAR = 39 / 1_000_000
PUBLIC = "https://pub-83c97a52f2e549718b126bf60f710f1a.r2.dev/shows"


def first_number(lang):
    """Episodes are numbered across days (EP 1 is the show's first), so a
    new day starts after the last one published; re-making a day keeps its
    numbers."""
    try:
        with urllib.request.urlopen(f"{PUBLIC}/{lang}/latest.json", timeout=15) as r:
            last = json.load(r)
    except Exception:
        return 1
    numbers = [e.get("number", 0) for e in last.get("episodes", [])]
    if last.get("date") == TODAY:
        return min(numbers) if numbers else 1
    return (max(numbers) if numbers else 0) + 1


def post(url, body, headers):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json",
                                          "User-Agent": "fv-news-show-probe", **headers})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


# The app's own languages. Every line ships with its meaning in each of these
# (one call per episode per language, made once for everybody); a learner
# with another native language falls back to the app's per-line Translator.
NATIVES = ["ko", "ja", "zh-Hant", "zh-Hans", "es", "fr", "de", "en"]
NATIVE_NAME = {"ko": "Korean", "ja": "Japanese", "zh-Hant": "Traditional Chinese (Taiwan)",
               "zh-Hans": "Simplified Chinese", "es": "Spanish", "fr": "French",
               "de": "German", "en": "English"}


def gemini(system, user, search=False, max_tokens=8192, model=None):
    body = {
        "contents": [{"role": "user", "parts": [{"text": user}]}],
        "generationConfig": {"maxOutputTokens": max_tokens,
                             "thinkingConfig": {"thinkingLevel": "low"}},
    }
    if system:
        body["system_instruction"] = {"parts": [{"text": system}]}
    if search:
        body["tools"] = [{"google_search": {}}]
    else:
        body["generationConfig"]["responseMimeType"] = "application/json"
    data = json.loads(post(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model or MODEL}:generateContent?key={GEMINI_KEY}",
        body, {}))
    cand = data["candidates"][0]
    text = "".join(p.get("text", "") for p in cand["content"]["parts"])
    if search:
        gm = cand.get("groundingMetadata", {})
        sources = [{"site": c["web"].get("title"), "uri": c["web"].get("uri")}
                   for c in gm.get("groundingChunks", []) if c.get("web")]
        return text, {"queries": gm.get("webSearchQueries", []), "sources": sources}
    start, end = text.find("{"), text.rfind("}")
    return json.loads(text[start:end + 1])


def pick_topics(lang):
    # Two steps. A system prompt asking for JSON made the model answer from
    # memory (3 of 3 runs never searched), and a pick from memory is old or
    # invented news. Asked in the user turn, in prose, it searched 3 of 3.
    research = (
        f"Search the web now: what are the most talked-about news stories in {REGION[lang]} "
        f"today, {TODAY} (last 48 hours)? Give 10 from different areas (tech, science, sport, "
        "culture, money, everyday life, travel, food, health, politics), each with 6-8 facts: "
        "what happened, who, when, key numbers, reactions."
    )
    for _ in range(3):
        notes, grounding = gemini(None, research, search=True)
        if grounding["sources"]:
            break
    else:
        sys.exit(f"[{lang}] the model never searched; no topics")

    system = (
        f"From the RESEARCH below, pick the {EPISODES} stories people in {REGION[lang]} would "
        f"most enjoy talking about over coffee. They become episodes of a daily podcast for "
        f"{LANG_NAME[lang]} learners (level {LEVEL}).\n"
        "- Each from a DIFFERENT area. At most one about politics.\n"
        "- None whose core is deaths, violence or a disaster: a learner should be able to "
        "chat about it lightly.\n"
        "- Facts only from the RESEARCH, nothing added.\n\n"
        "Return JSON:\n"
        '{ "topics": [ { "title": "...", "area": "...", "facts": ["...", "..."] } ] }\n'
        f"- title: a short episode title in {LANG_NAME[lang]}, 8 words or fewer.\n"
        "- area: one English word.\n"
        f"- facts: 6-8 plain facts in {LANG_NAME[lang]}, each 25 words or fewer."
    )
    parsed = gemini(system, "RESEARCH:\n" + notes)
    grounding["research"] = notes
    return parsed.get("topics", [])[:EPISODES], grounding


INVENTED_VOICES = re.compile(
    r"\b(listeners?|readers?|wrote (in|to us)|messaged us|caller|Hörer\w*|Leser\w*|"
    r"(hat|haben) uns (\w+ )?geschrieben|Zuschauer\w*)\b", re.I)


def write_script(lang, topic):
    # Asked twice not to, the model still slipped in "a listener wrote in"
    # (1 of 10 episodes on the first day). A made-up person quoted as real
    # is the one thing a news show can't say, so it is caught here too.
    for _ in range(3):
        script = _write_script(lang, topic)
        said = " ".join(l["text"] for l in script["lines"])
        if not INVENTED_VOICES.search(said):
            return script
    return script


def _write_script(lang, topic):
    (a, _), (b, _) = HOSTS[lang]
    system = (
        f"Write one episode of a daily news podcast for {LANG_NAME[lang]} learners at "
        f"level {LEVEL}. Two hosts, {a} and {b}, friends who have done the show together "
        f"for a while, talk one news story through. Everything in {LANG_NAME[lang]}.\n\n"
        "SHAPE\n"
        f"- 550-650 words in total (about 4 minutes), 24-30 turns, alternating, {a} first. "
        "Count: a 300-word episode is too short.\n"
        "- The show is the nawana Podcast: say its name once in the opening.\n"
        "- A short warm opening that names the show's topic, then the story: what happened, "
        "why it matters, what each of them thinks, one everyday angle a listener shares. "
        "Close with one line that hands the question to the listener.\n"
        "- It is SPOKEN, the way two friends actually talk: contractions always where a "
        "native would use them (I'm, don't, it's; German: ich hab, gibt's, so 'n bisschen "
        "only where natural), short reactions (Really? / Oh wow. / Echt?), follow-up "
        "questions, a host rephrasing a harder word in simpler words now and then.\n"
        "- Vary the turns: some are two words, most are 2-3 sentences. A show of one "
        "sentence per turn sounds read aloud.\n\n"
        f"LEVEL {LEVEL}\n"
        "- Everyday vocabulary and clear sentence shapes; no idiom stacking, no jargon left "
        "unexplained. Easier words, not a thinner conversation.\n\n"
        "FACTS\n"
        "- Every fact, name and number comes from the FACTS below. Opinions are the hosts' "
        "own and are said as opinions. Never invent a quote, a figure or a detail.\n"
        "- NOBODY but the two hosts exists: no listener or reader messages (\"a listener wrote "
        "in\", \"eine Leserin hat uns geschrieben\"), no callers, guests, polls, comments. "
        "The hosts may say how a thing touches everyday life in general, never a made-up "
        "event from their own lives.\n"
        "- Say the date of the news only if it matters, and as people say it (\"on Sunday\", "
        "\"last week\"), never the full year.\n\n"
        "PUNCTUATION IS THE BREATH\n"
        "- A period ends a finished thought, a comma only where the voice should hang. No "
        "dashes between clauses (a hyphen inside a word is fine), no ellipses, no emoji, no stage directions, no sound effects.\n\n"
        f"Return STRICT JSON only (title in {LANG_NAME[lang]}, 8 words or fewer):\n"
        '{ "title": "...", "lines": [ { "speaker": "' + a + '", "text": "..." } ], '
        '"expressions": [ { "phrase": "...", "line": 0 } ] }\n'
        "- expressions: the 5 most reusable phrases the hosts used (chunks a learner can "
        "say tomorrow, not single easy words), each with the index of the line it is in."
    )
    user = f"TITLE: {topic['title']}\nFACTS:\n" + "\n".join(f"- {f}" for f in topic["facts"])
    return gemini(system, user)


def tts_pcm(voice, text, lang):
    return post("https://api.cartesia.ai/tts/bytes", {
        "model_id": "sonic-3.6",
        "transcript": text,
        "voice": {"mode": "id", "id": voice},
        "language": lang,
        "output_format": {"container": "raw", "encoding": "pcm_s16le", "sample_rate": SAMPLE_RATE},
        "generation_config": {"speed": CARTESIA_SPEED, "emotion": "neutral"},
    }, {"Authorization": f"Bearer {CARTESIA_KEY}", "Cartesia-Version": "2026-08-14"})


def trim(pcm):
    """Cut each clip's edge silence to the voice, as PacedSpeech does, so the
    gaps between sentences are the ones we put there."""
    n = len(pcm) // 2
    samples = struct.unpack(f"<{n}h", pcm[:n * 2])
    block = SAMPLE_RATE // 100
    rms = [max(abs(x) for x in samples[i:i + block]) for i in range(0, n, block)]
    peak = max(rms) if rms else 0
    gate = peak * 0.06
    voiced = [i for i, v in enumerate(rms) if v > gate]
    if not voiced:
        return b""
    start = max(0, voiced[0] - 2) * block
    end = min(n, (voiced[-1] + 4) * block)
    return pcm[start * 2:end * 2]


def sentences(text):
    parts = re.split(r"(?<=[.!?])\s+(?=[A-ZÄÖÜ\"'])", text.strip())
    return [p for p in parts if p.strip()]


def silence(seconds):
    return b"\x00\x00" * int(SAMPLE_RATE * seconds)


def wav_bytes(pcm):
    return (b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt " +
            struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16) +
            b"data" + struct.pack("<I", len(pcm)) + pcm)


def to_mp3(pcm, path, bitrate):
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "wav", "-i", "pipe:0",
                    "-ac", "1", "-b:a", bitrate, path], input=wav_bytes(pcm), check=True)


def translate_lines(lang, texts):
    """Each line's meaning in every native language, keyed like the app's
    `nativeLanguage`. The same model and instruction as the app's own
    `translate` function, a whole episode per call."""
    out = [{} for _ in texts]

    def one(native):
        system = (f"You are a translator. Translate each line into {NATIVE_NAME[native]}. "
                  "Translate it as said, naturally, one line for one line. No quotes, no "
                  "romanization, no notes, no original text.\n"
                  'Return JSON: { "lines": ["...", ...] } with exactly as many lines as given.')
        user = json.dumps({"lines": texts}, ensure_ascii=False)
        for _ in range(2):
            got = gemini(system, user, model="gemini-3.1-flash-lite").get("lines", [])
            if len(got) == len(texts) and all(isinstance(t, str) and t.strip() for t in got):
                return native, got
        return native, None

    with cf.ThreadPoolExecutor(4) as pool:
        for native, got in pool.map(one, [n for n in NATIVES if n != lang]):
            if got:
                for i, t in enumerate(got):
                    out[i][native] = t.strip()
    return out


def make_episode(lang, idx, topic, folder):
    """One episode as ONE file (the podcast) and one file PER LINE (the
    app's player plays and captions a line at a time, like a scene)."""
    script = write_script(lang, topic)
    voices = dict(HOSTS[lang])
    pieces = []  # (line index, speaker, sentence)
    for i, line in enumerate(script["lines"]):
        for s in sentences(line["text"]):
            pieces.append((i, line["speaker"], s))
    with cf.ThreadPoolExecutor(4) as pool:
        clips = list(pool.map(lambda p: trim(tts_pcm(voices.get(p[1], HOSTS[lang][0][1]), p[2], lang)),
                              pieces))

    # A line's own sentences, PacedSpeech's gap between them.
    line_pcm = [bytearray() for _ in script["lines"]]
    for (i, _, _), clip in zip(pieces, clips):
        if line_pcm[i]:
            line_pcm[i] += silence(SENTENCE_GAP)
        line_pcm[i] += clip

    os.makedirs(os.path.join(folder, "lines"), exist_ok=True)
    episode = bytearray(silence(0.4))
    for i, pcm in enumerate(line_pcm):
        name = f"{i:03d}.mp3"
        to_mp3(bytes(pcm), os.path.join(folder, "lines", name), "64k")
        script["lines"][i]["audio"] = f"lines/{name}"
        if i:
            episode += silence(TURN_GAP)
        episode += pcm
    episode += silence(0.8)
    to_mp3(bytes(episode), os.path.join(folder, "episode.mp3"), "128k")

    for line, meaning in zip(script["lines"], translate_lines(lang, [l["text"] for l in script["lines"]])):
        line["translations"] = meaning
    chars = sum(len(p[2]) for p in pieces)
    script["facts"] = topic["facts"]
    script["area"] = topic.get("area", "news")
    with open(os.path.join(folder, "script.json"), "w") as f:
        json.dump(script, f, ensure_ascii=False, indent=2)
    with open(os.path.join(folder, "script.txt"), "w") as f:
        f.write(script.get("title", topic["title"]) + "\n\n")
        f.write("\n".join(f"{l['speaker']}: {l['text']}" for l in script["lines"]))
        f.write("\n\nExpressions:\n" + "\n".join(f"- {e['phrase']}" for e in script.get("expressions", [])))
    seconds = len(episode) / 2 / SAMPLE_RATE
    words = sum(len(l["text"].split()) for l in script["lines"])
    return {"idx": idx, "title": script.get("title", topic["title"]), "seconds": round(seconds),
            "words": words, "chars": chars, "script": script}


def add_translations(day_dir):
    """Give a day made before translations shipped its meanings, in place."""
    for lang in os.listdir(day_dir):
        path = os.path.join(day_dir, lang, "show.json")
        if not os.path.exists(path):
            continue
        show = json.load(open(path))
        for ep in show["episodes"]:
            meanings = translate_lines(lang, [l["text"] for l in ep["lines"]])
            for line, meaning in zip(ep["lines"], meanings):
                line["translations"] = meaning
            print(f"  [{lang}] EP {ep.get('number')}: {len(meanings[0]) if meanings else 0} languages")
        json.dump(show, open(path, "w"), ensure_ascii=False, indent=2)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--translate":
        return add_translations(sys.argv[2])
    if os.path.exists(OUT) and os.listdir(OUT):
        sys.exit(f"{OUT} already has files; set OUT_DIR to another folder")
    total_chars = 0
    for lang in LANGS:
        topics, sources = pick_topics(lang)
        base = os.path.join(OUT, lang)
        os.makedirs(base, exist_ok=True)
        with open(os.path.join(base, "topics.json"), "w") as f:
            json.dump({"topics": topics, **sources}, f, ensure_ascii=False, indent=2)
        print(f"[{lang}] {len(topics)} topics")
        episodes = []
        start = first_number(lang)
        for i, t in enumerate(topics, 1):
            slug = f"{i:02d}-{re.sub(r'[^A-Za-z0-9]+', '-', t.get('area', 'news')).strip('-').lower()}"
            r = make_episode(lang, i, t, os.path.join(base, slug))
            total_chars += r["chars"]
            sc = r["script"]
            # The manifest the app reads: paths are relative to shows/<lang>/.
            episodes.append({
                "id": f"{TODAY}-{lang}-{i:02d}",
                "number": start + i - 1,
                "title": sc.get("title", t["title"]),
                "area": sc["area"],
                "seconds": r["seconds"],
                "audio": f"{TODAY}/{slug}/episode.mp3",
                "lines": [{"speaker": l["speaker"], "text": l["text"],
                           "audio": f"{TODAY}/{slug}/{l['audio']}",
                           "translations": l.get("translations", {})} for l in sc["lines"]],
                "expressions": [e.get("phrase", "") for e in sc.get("expressions", [])],
            })
            print(f"  {i}. {r['title']}  {r['seconds'] // 60}:{r['seconds'] % 60:02d}  "
                  f"{r['words']} words  {r['chars']} chars  ${r['chars'] * USD_PER_CHAR:.2f}")
        with open(os.path.join(base, "show.json"), "w") as f:
            json.dump({"date": TODAY, "language": lang,
                       "hosts": [h[0] for h in HOSTS[lang]], "episodes": episodes},
                      f, ensure_ascii=False, indent=2)
    print(f"TTS total {total_chars} chars ≈ ${total_chars * USD_PER_CHAR:.2f}  →  {OUT}")


if __name__ == "__main__":
    main()
