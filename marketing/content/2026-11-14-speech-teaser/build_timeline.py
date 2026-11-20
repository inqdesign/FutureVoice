#!/usr/bin/env python3
"""Build the teaser's sound and timeline from the challenges' own fluent readings.

Each person says the opening of their real challenge reading (media/voice/r*.wav, the listening
readings in R2, rows.json = speech_listen_audio with word times) and is cut off just after the next
word starts. Then everyone talks at once, and each voice stops when its light goes out. Silence for
the end card. Writes media/track.wav (48 kHz mono) and timeline.js (window.TL), which teaser.html reads.

  python3 marketing/content/2026-11-14-speech-teaser/build_timeline.py
"""
import json, os, re, wave
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
SR = 48000
rows = json.loads((HERE / "media/voice/rows.json").read_text())


def reading(i):
    w = wave.open(str(HERE / f"media/voice/r{i}.wav"))
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    x = np.interp(np.arange(0, len(x) * 2) / 2, np.arange(len(x)), x)  # 24k → 48k
    words = rows[i]["words"]
    words = words if isinstance(words, list) else json.loads(words)
    return x, words


BODY = {r["k"]: r["body"].split() for r in json.loads((HERE / "media/voice/bodies.json").read_text())}
READING_BODY = {3: "010", 1: "02c", 0: "02b", 4: "005", 2: "025", 7: "02d", 9: "020", 8: "00b", 6: "024"}
WINDOW = 30   # words of the script on screen around the line (founder 2026-11-15: show more of the script)


def window(ri, k0, k1):
    """The script's own words around tokens k0..k1-1 (reading indices = body indices, checked):
    from the start of k0's sentence (at most 10 back), about WINDOW words, ending at a sentence end if one is near."""
    toks = BODY[READING_BODY[ri]]
    a = k0
    while a > 0 and k0 - a < 10 and not re.search(r"[.?!:]$", toks[a - 1]):
        a -= 1
    if a > 0 and not re.search(r"[.?!:]$", toks[a - 1]):
        a = k0
    b = max(k1, a + WINDOW)
    while b < len(toks) and b - (a + WINDOW) < 8 and not re.search(r"[.?!]$", toks[b - 1]):
        b += 1
    b = min(b, len(toks))
    return a, b, toks


norm = lambda s: re.sub(r"[^a-z']", "", s.lower().replace("’", "'"))

# img, reading, how long they get to talk (s), the opening as the script writes it
# The flight attendant opens the reading and is cut off (her talk time, in seconds). Everyone after says ONE
# signature line from the middle of their script, whole (founder 2026-11-14: openings alone were dull):
# (img, reading, first word index in the reading, the line as the script writes it). Longest first, so the cuts speed up.
SCENES = [
    ("0010", 3, 3.3, "Good evening, ladies and gentlemen, and welcome aboard this nawana Air flight to London."),
    ("002C", 1, ("from", 83), "Please take the big umbrella, not the cute one."),
    ("002B", 0, ("from", 163), "The police even questioned a young Pablo Picasso."),
    ("0005", 4, ("from", 110), "So is it worth starting later in life?"),
    ("0025", 2, ("from", 105), "I hate running. I really do."),
    ("002D", 7, ("from", 129), "I swear I forgot to breathe."),
    ("0020", 9, ("from", 180), "Three for the price of one."),
    ("000B", 8, ("from", 181), "Say it once: I'm excited."),
    ("0024", 6, ("from", 50), "Never give up."),
]
ROW = ["0001", "0005", "0010", "0020", "0024", "0025", "002B", "002C", "002D", "000B"]
ROW_VOICE = {"0024": 6, "0005": 4, "0010": 3, "0020": 9, "0025": 2, "002B": 0, "002C": 1, "002D": 7, "000B": 8}
# in the crowd each voice starts at its own line (the attendant at her opening)
ROW_FROM = {img: talk[1] for img, _, talk, _ in SCENES if isinstance(talk, tuple)}

MIC_END = 3.0            # the half-drawn mic: switched on, a throat cleared, then the first voice
SWITCH_AT, AHEM_AT = 0.25, 1.05
AHEM = os.environ.get("AHEM", "take1")   # media/ahem/take1–6 (Cartesia, the readings' female voice); pick by ear
track = np.zeros(int(40 * SR), np.float32)


def put(x, at, gain=1.0):
    a = int(at * SR)
    track[a:a + len(x)] += x * gain


def fade_out(x, ms):
    n = min(len(x), int(SR * ms / 1000))
    if n:
        x = x.copy(); x[-n:] *= np.cos(np.linspace(0, np.pi / 2, n)) ** 2   # smooth, no knee at the end
    return x


def switch_on():
    """A mic being switched on: a click and thump, mains hum, a faint feedback ring. Synthesized, ~1.1 s."""
    n = int(1.1 * SR); tt = np.arange(n) / SR
    rng = np.random.default_rng(7)
    click = rng.standard_normal(n) * np.exp(-tt / 0.004) * 0.55
    thump = np.sin(2 * np.pi * 70 * tt) * np.exp(-tt / 0.06) * 0.5
    env = np.clip(tt / 0.04, 0, 1) * np.exp(-np.clip(tt - 0.25, 0, None) / 0.3)
    hum = (np.sin(2 * np.pi * 60 * tt) + .5 * np.sin(2 * np.pi * 120 * tt) + .3 * np.sin(2 * np.pi * 180 * tt)) * env * 0.05
    ring_env = np.clip((tt - 0.08) / 0.25, 0, 1) * np.exp(-np.clip(tt - 0.33, 0, None) / 0.18)
    ring = np.sin(2 * np.pi * (2450 * tt + 6 * np.sin(2 * np.pi * 5 * tt))) * ring_env * 0.035
    return click + thump + hum + ring


def ahem():
    w = wave.open(str(HERE / f"media/ahem/{AHEM}.wav"))
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    if w.getframerate() != SR:
        x = np.interp(np.arange(0, len(x) * SR / w.getframerate()) * w.getframerate() / SR, np.arange(len(x)), x)
    on = np.flatnonzero(np.abs(x) > 0.02)
    return fade_out(x[max(0, on[0] - 480):on[-1] + 2400], 60) if len(on) else x


# no sound effects (founder 2026-11-14: the switch-on and the ahem were cut); the opening is silent

tl = {"micEnd": MIC_END, "scenes": [], "row": []}
t = MIC_END
for img, ri, talk, text in SCENES:
    sc = {"img": img, "start": round(t, 3), "words": []}
    if isinstance(talk, tuple):                            # a signature line, said whole
        x, words = reading(ri)
        shown = text.split()
        w = words[talk[1]:talk[1] + len(shown)]
        for k, tok in enumerate(shown):
            assert norm(tok) == norm(w[k]["w"]), (img, tok, w[k]["w"])
        lead = max(0, w[0]["s"] - 60) / 1000
        end = w[-1]["e"] / 1000 + 0.22                    # the last word rings out, then fades
        put(fade_out(x[int(lead * SR):int(end * SR)], 200), t)
        a, b, toks = window(ri, talk[1], talk[1] + len(shown))
        k0 = talk[1]
        sc["words"] = [{"w": toks[j],
                        "at": round(t + words[j]["s"] / 1000 - lead, 3) if k0 <= j < k0 + len(shown) else None,
                        "end": round(t + words[j]["e"] / 1000 - lead, 3) if k0 <= j < k0 + len(shown) else None}
                       for j in range(a, b)]
        sc["more"] = b < len(toks)
        sc["end"] = round(t + end - lead + 0.12, 3)
    elif ri is None:
        sc["end"] = round(t + talk, 3)
    else:
        x, words = reading(ri)
        shown = text.split()
        for k, tok in enumerate(shown):                    # the script's words are the reading's, one by one
            assert norm(tok) == norm(words[k]["w"]), (img, tok, words[k]["w"])
        lead = max(0, words[0]["s"] - 60) / 1000
        n = max(2, sum(1 for w in words[:len(shown)] if (w["e"] / 1000 - lead) <= talk))
        cut = words[n]["s"] / 1000 + 0.24 if n < len(words) else words[n - 1]["e"] / 1000   # into the next word
        if n < len(words) and words[n]["s"] - words[n - 1]["e"] > 200:   # a breath first: skip it, cut into the word after
            gap = (words[n]["s"] - words[n - 1]["e"]) / 1000 - 0.08
            x = np.concatenate([x[:int(words[n - 1]["e"] / 1000 * SR) + int(0.04 * SR)], x[int(words[n]["s"] / 1000 * SR) - int(0.04 * SR):]])
            words = [dict(w, s=w["s"] - gap * 1000 * (k >= n), e=w["e"] - gap * 1000 * (k >= n)) for k, w in enumerate(words)]
            cut = words[n]["s"] / 1000 + 0.24
        seg = fade_out(x[int(lead * SR):int(cut * SR)], 200)   # the voice fades as it is cut, never a click
        put(seg, t)
        # the whole line, dim; a word lights from when it starts to when it ends; the words after the cut stay dim
        a, b, toks = window(ri, 0, n)
        sc["words"] = [{"w": toks[j],
                        "at": round(t + words[j]["s"] / 1000 - lead, 3) if j < n else None,
                        "end": round(t + words[j]["e"] / 1000 - lead, 3) if j < n else None} for j in range(a, b)]
        sc["more"] = b < len(toks)
        sc["end"] = round(t + cut - lead, 3)
    tl["scenes"].append(sc)
    t = sc["end"]

# everyone at once: they land one every 0.22 s and start talking; the lights go out right to left, 0.24 s apart
ROW_START = t
land = [ROW_START + i * 0.22 for i in range(len(ROW))]
SETTLE = ROW_START + 2.9   # everyone stays (founder 2026-11-15: nobody disappears); they settle to the bottom
VOICE_FADE = 2.2           # and their voices fade out together, under the mic drawing
for i, img in enumerate(ROW):
    tl["row"].append({"img": img, "land": round(land[i], 3)})
    if img in ROW_VOICE:
        x, words = reading(ROW_VOICE[img])
        lead = max(0, words[ROW_FROM.get(img, 0)]["s"] - 60) / 1000
        seg = x[int(lead * SR):int((lead + SETTLE - land[i] + VOICE_FADE) * SR)].copy()
        k = int(0.03 * SR); seg[:k] *= np.linspace(0, 1, k)            # in softly as they land
        put(fade_out(seg, VOICE_FADE * 1000), land[i], 0.42)
tl["everyone"] = round(land[-1] + 0.35, 3)
tl["settle"] = round(SETTLE, 3)
tl["rowEnd"] = 1e9
tl["cream"] = round(SETTLE + 0.3, 3)       # key name kept: the mic finishes drawing, above the crowd
tl["turn"] = round(SETTLE + VOICE_FADE + 0.25, 3)
tl["soon"] = round(tl["turn"] + 0.6, 3)
tl["total"] = round(tl["soon"] + 2.2, 3)

track = track[:int(tl["total"] * SR)]
track *= 0.89 / max(1e-6, np.abs(track).max())
with wave.open(str(HERE / "media/track.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((track * 32767).astype(np.int16).tobytes())
(HERE / "timeline.js").write_text("// written by build_timeline.py\nwindow.TL = " + json.dumps(tl, indent=1) + ";\n")
for s in tl["scenes"]:
    print(s["img"], s["start"], s["end"], " ".join(w["w"] for w in s["words"]))
print("row", ROW_START, "end", tl["rowEnd"], "total", tl["total"])
