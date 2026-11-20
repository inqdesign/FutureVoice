#!/usr/bin/env python3
# Synthesizes every scene line (and, with copy.json present, the narration) once. Cached by file: re-runs cost nothing.
import json, os, urllib.request, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "../../.."))
VARS = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)
KEY = VARS["CARTESIA_API_KEY"].strip().strip('"')
SR = 44100
HARIN, OFFICER = "999df508-4de5-40a7-8bd3-8c12f678c284", "c961b81c-a935-4c17-bfb3-ba2239de8c2f"
NARRATOR = "cac92886-4b7c-4bc1-a524-e0f79c0381be"
def tts(voice, text, lang, out, speed=0.95):
    if os.path.exists(out): return
    req = urllib.request.Request("https://api.cartesia.ai/tts/bytes", json.dumps({
        "model_id": "sonic-3.6", "transcript": text, "voice": {"mode": "id", "id": voice}, "language": lang,
        "output_format": {"container": "raw", "encoding": "pcm_s16le", "sample_rate": SR},
        "generation_config": {"speed": speed, "emotion": "neutral"}}).encode(),
        {"Authorization": f"Bearer {KEY}", "Cartesia-Version": "2026-08-14", "Content-Type": "application/json"})
    open(out, "wb").write(urllib.request.urlopen(req, timeout=120).read()); print("made", os.path.basename(out))
os.makedirs(os.path.join(HERE, "audio"), exist_ok=True)
s = json.load(open(os.path.join(HERE, "scene.json")))
for i, t in enumerate(s["turns"]):
    tts(HARIN if t["speaker"] == "user" else OFFICER, t["text"], "en", os.path.join(HERE, f"audio/line{i:02d}.pcm"))
p = os.path.join(HERE, "copy.json")
if os.path.exists(p):
    for k, v in json.load(open(p))["narration"].items():
        tts(NARRATOR, v, "ko", os.path.join(HERE, f"audio/n_{k}.pcm"), speed=1.0)
