#!/usr/bin/env python3
"""Synthesizes the weekly test's four answer sounds into FutureVoice/Resources.

Nothing sampled, nothing licensed: pure sine partials with a fast attack and
an exponential tail, quiet (peak -12 dBFS) so they sit under a voice and
never startle. 44.1 kHz, 16-bit mono WAV, the format AudioServices plays.

    python3 scripts/make-ui-sounds.py
"""
import math, struct, wave, pathlib

RATE = 44_100
OUT = pathlib.Path(__file__).resolve().parent.parent / "FutureVoice" / "Resources"

def tone(freq, dur, gain=1.0, decay=6.0, partials=((1, 1.0), (2, 0.25), (3, 0.08))):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.004) * math.exp(-decay * t)
        v = sum(a * math.sin(2 * math.pi * freq * k * t) for k, a in partials)
        out.append(v * env * gain)
    return out

def mix(*layers):
    n = max(len(l) for l in layers)
    return [sum(l[i] if i < len(l) else 0.0 for l in layers) for i in range(n)]

def offset(samples, seconds):
    return [0.0] * int(RATE * seconds) + samples

def write(name, samples, peak_db=-12.0):
    peak = max(abs(s) for s in samples) or 1.0
    target = 10 ** (peak_db / 20)
    scale = target / peak
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(data)
    print(name, f"{len(samples)/RATE:.2f}s")

# tap: a keyboard-style tock for laying a tile or picking a choice — a
# 25 ms burst of noise for the "click" over a short low body for the "tock".
import random
random.seed(7)
def noise(dur, decay):
    n = int(RATE * dur); out = []; prev = 0.0
    for i in range(n):
        t = i / RATE
        # one-pole low-pass on white noise keeps it from hissing
        prev = prev * 0.6 + (random.random() * 2 - 1) * 0.4
        out.append(prev * min(1.0, t / 0.001) * math.exp(-decay * t))
    return out
write("test-tap.wav", mix(noise(0.035, 120), tone(420, 0.06, gain=0.8, decay=70, partials=((1, 1.0), (2, 0.2)))),
      peak_db=-14.0)
# right: two notes up, a fifth apart — resolved, not fanfare.
write("test-right.wav", mix(tone(660, 0.35, decay=9), offset(tone(990, 0.4, decay=7), 0.08)))
# wrong: one low, soft note — information, not a punishment.
write("test-wrong.wav", tone(220, 0.35, decay=8, partials=((1, 1.0), (2, 0.15))))
# done: a rising triad, still quiet.
write("test-done.wav", mix(tone(523, 0.6, decay=5), offset(tone(659, 0.6, decay=5), 0.11),
                           offset(tone(784, 0.8, decay=4), 0.22)))
