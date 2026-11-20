#!/usr/bin/env python3
# Writes scene.json with the app's Watch scene prompt (ScenarioCurriculumEngine.systemPrompt, B1, en).
import json, os, urllib.request
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
VARS = dict(l.split("=", 1) for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if "=" in l)
KEY = VARS["GEMINI_API_KEY"].strip().strip('"')
SYSTEM = """You are a English curriculum designer. Given ONE real-life
scenario a learner (CEFR B1) wants to master, write the SCENE
for it: a naturalistic dialogue between the learner ("user") and the
other person ("counterpart"), then extract the study content FROM that
dialogue. The dialogue is the whole course — the learner watches it,
studies its words and expressions, and shadows their own lines.

WHOSE SITUATION IT IS — settle this before you write a line. The
scenario is the learner's own. Whatever it names being done, the LEARNER ("user") is the one doing it, and the
counterpart is the person on the OTHER side of it.

Content rules:
- turns: 8 to 10, alternating naturally. The counterpart opens when
  the situation is something that happens TO the learner (called in by
  the doctor, served at a counter, stopped by an official).
  Real spoken English — contractions, hedges, natural register.
  PUNCTUATE LIKE SPEECH. A FINISHED sentence always ends with a period, question mark or exclamation mark, never a comma. Two sentences that could each stand alone are NEVER joined by a bare comma. A comma belongs only INSIDE a sentence, where the voice should hang and breathe.
  Each turn is 1–2 sentences — as long as the moment naturally calls
  for, never padded to reach the count and never clipped mid-thought.
  The USER speaks as a confident, fluent version of the learner
  (slightly above B1, never textbook-stiff). Every user turn must
  be a complete, speakable line — it will be shadowed ALOUD. No stage
  directions, brackets, or placeholders anywhere.
- words: 8 single words or short compounds that APPEAR in the dialogue
  and a B1 learner plausibly doesn't own yet. note = one short cue for when it comes up.
  example = the dialogue sentence that uses it.
- expressions: 6 multi-word chunks (2–6 words) that APPEAR VERBATIM in
  the dialogue — collocations, softeners, transactional moves natives
  actually use here. note = one short cue for when to reach for it.
  example = the dialogue sentence that uses it.
- title: 2–5 words in English naming what happens in THIS scene.
- Everything specific to THIS scenario and persona — never generic
  textbook content.

SUBSTANCE — Something has to actually HAPPEN:
the specific thing the learner is going in to do, the complication it
runs into, the question that is hard to answer, and how it lands.

WHAT B1 CHANGES — the words and the sentence shapes, and nothing else.
- Vocabulary: Everyday vocabulary plus the common idioms and phrasal verbs a fluent speaker actually reaches for. Specialist or abstract words are fine when the sentence around them makes the meaning clear; drop one genuinely new word in now and then, not every turn.
- Sentence shapes: Subordinate clauses and natural hedging are welcome.

Return STRICT JSON only:
{"turns": [{"speaker": "user"|"counterpart", "text": "..."}], "title": "...", "words": [{"text":"...","note":"...","example":"..."}], "expressions": [{"text":"...","note":"...","example":"..."}]}"""
USER = """scenario:
- what the learner is going in to do (their own words): my student visa interview at the US embassy in Seoul, for a master's in business
- talking to: a US consular officer at the interview window
- context: The learner is Harin, 28, from Korea. Three years on the marketing team of a mid-sized company in Seoul. Admitted to a master's in business at a university in the US. NEVER name any school or company: say "the university" or "my company". Tuition comes from her own savings plus her parents. She wants to come back and work in marketing for Korean brands going overseas. The hard part: the officer asks why she would leave a good job, and doubts she will come back after the degree. She answers calmly and it ends with the visa being approved. Keep every line plain and spoken: everyday words, nothing a person would not say out loud."""
body = {"system_instruction": {"parts": [{"text": SYSTEM}]}, "contents": [{"role": "user", "parts": [{"text": USER}]}],
        "generationConfig": {"maxOutputTokens": 3000, "thinkingConfig": {"thinkingLevel": "low"}, "responseMimeType": "application/json"}}
r = urllib.request.urlopen(urllib.request.Request(
    f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={KEY}",
    json.dumps(body).encode(), {"Content-Type": "application/json"}), timeout=120)
d = json.load(r); t = "".join(p.get("text", "") for p in d["candidates"][0]["content"]["parts"])
s = json.loads(t[t.find("{"):t.rfind("}")+1])
json.dump(s, open(os.path.join(os.path.dirname(__file__), "scene.json"), "w"), ensure_ascii=False, indent=1)
for x in s["turns"]: print(f'{x["speaker"][:4]}: {x["text"]}')
print(s["title"]); print(s["expressions"]); print(sum(len(x["text"]) for x in s["turns"]))
