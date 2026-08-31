#!/usr/bin/env python3
"""List Gemini models that support the Live (bidi) API, using the same key
the edge functions run on (.dev.vars). Prints model names only — never the key.
"""
import json
import pathlib
import urllib.request

env = dict(
    line.split("=", 1)
    for line in pathlib.Path(__file__).resolve().parents[1].joinpath(".dev.vars")
        .read_text().splitlines()
    if "=" in line
)
key = env["GEMINI_API_KEY"]

url = f"https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&key={key}"
with urllib.request.urlopen(url) as r:
    data = json.loads(r.read().decode())

models = data.get("models", [])
print("total models:", len(models))
for m in models:
    methods = m.get("supportedGenerationMethods", [])
    if any("bidi" in x.lower() for x in methods) or "live" in m["name"].lower():
        print(f"{m['name']}  {methods}")
