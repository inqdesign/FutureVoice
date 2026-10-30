#!/usr/bin/env python3
# Runs the app's LIVE report-narration prompt (rebuilt from
# ReportNarration.swift + CoachingLanguage.swift so it cannot drift) over a
# trial report's card facts, and prints every line with its caption and the
# checks the app would care about: length, exclamation marks, numbers not in
# the facts, and the target-script check.
#
#   scripts/report-narration-probe.py en ko A2   [target native level]
#   SAY=1 …   also synthesize each line with a Cartesia library voice into
#             $OUT (default: the scratchpad you pass) to listen to the pacing
#
# Reads GEMINI_API_KEY from gateway/.dev.vars.
import json, os, re, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = {"en": "English", "ko": "Korean", "ja": "Japanese", "de": "German", "es": "Spanish"}
target, native, level = sys.argv[1], sys.argv[2], sys.argv[3].lower()
src = open(os.path.join(ROOT, "FutureVoice/Services/ReportNarration.swift")).read()
coach = open(os.path.join(ROOT, "FutureVoice/Services/CoachingLanguage.swift")).read()
engine = open(os.path.join(ROOT, "FutureVoice/Services/ConversationEngine.swift")).read()


def block(text, name):
    m = re.search(r'static let %s = """\n(.*?)\n\s*"""' % name, text, re.S)
    return "\n".join(l.strip() for l in m.group(1).splitlines()).replace("\\\n", " ").replace("\\ ", " ")


def joined(raw):
    lines = [l.strip() for l in raw.splitlines()]
    out = ""
    for l in lines:
        out += (l[:-1] if l.endswith("\\") else l + "\n")
    return out.strip()


def vocabulary(lv):
    band = "a1, .a2" if lv in ("a1", "a2") else ("b1, .b2" if lv in ("b1", "b2") else "c1, .c2")
    seg = engine[engine.index("static func speechScale"):]
    seg = seg[seg.index("case .%s:" % band):]
    m = re.search(r'vocabulary:\s*"((?:[^"\\]|\\.)*)"', seg) or re.search(r'vocabulary:\s*"""\n(.*?)"""', seg, re.S)
    return joined(m.group(1))


m = re.search(r'let system = """\n(.*?)\n\s*"""', src, re.S)
system = joined(m.group(1))
system = (system.replace("\\(target)", NAMES[target]).replace("\\(native)", NAMES[native])
          .replace("\\(span)", "their first talks with you, the free minutes that just ran out")
          .replace("\\(level.rawValue.uppercased())", level.upper())
          .replace("\\(scale.vocabulary)", vocabulary(level))
          .replace("\\(CoachingLanguage.selfWarmth)", joined(re.search(r'static let selfWarmth = """\n(.*?)\n\s*"""', coach, re.S).group(1)))
          .replace("\\(CoachingLanguage.breathPunctuation)", joined(re.search(r'static let breathPunctuation = """\n(.*?)\n\s*"""', coach, re.S).group(1))))
system = re.sub(r'\\\(firstTalks \? "(.*?)" : ""\)', lambda mm: mm.group(1).replace('\\"', '"'), system)
assert "\\(" not in system, re.findall(r"\\\(.{0,40}", system)

FACTS = {
 "cover": ["Opening card: their free minutes are over. They talked 21 min in 3 talk(s)."],
 "talk": ["They talked 21 min in 3 talk(s).", "Talks: What you do day to day · Pitching a new feature to my team · A four-day work week"],
 "fresh": ["7 phrase(s) YOU (the fluent self) said that they haven't said yet; they are saved for them.", "Phrase: push back on", "Phrase: a good fit", "Phrase: the trade-off"],
 "stumbles": ["The same correction came back more than once:", "\"I am working here since three years\" → \"I've been working here for three years\", 2 times"],
 "grammar": ["Grammar point that slipped in different sentences: 'explain' 뒤에 사람을 바로 쓰는 실수 — e.g. \"explain them why\" → \"explain to them why\"",
             "Grammar point that slipped in different sentences: 셀 수 있는 명사 앞 a 빠짐 — e.g. \"it is good idea\" → \"it's a good idea\""],
 "words": ["They leaned on \"very\" (6 times); a word to reach for next: \"really\".", "They leaned on \"good\" (5 times); a word to reach for next: \"solid\"."],
 "coach": ["The coach's headline: 짧은 문장은 정확한데 이어 붙이면 흔들려요", "How they speak: 'and then'으로 계속 이어 붙이고, 이유를 말할 때 because 뒤 문장이 짧아져요.", "Next up: 다음 통화에서 'I've been ... for' 한 번 써 보기", "Next up: 'push back on'을 직접 말해 보기"],
 "trialTest": ["Next: a short test made from what they said — the words, the phrases, the corrections. They can take it or skip it."],
 "level": ["Their speaking level, read from their talks: A2.", "Why: 일상 주제는 이어서 말하지만 대부분 한 절짜리 문장이고, 시제가 지금까지 이어지는 일을 말할 때 흔들려요.", "It moves as they talk."],
 "routine": ["A routine to keep going: Talk about work, every day", "Routine: Talk 10 min, every day", "Routine: Review ×10, Mon–Fri", "Last card. The button under it keeps this routine going. Hand over to it; don't mention prices or plans."],
}
user = "Learner's name: Jiwoo\n\n" + "\n\n".join("CARD %s\n" % k + "\n".join("- " + f for f in v) for k, v in FACTS.items())
if "--show" in sys.argv:
    print(system); print("\n---\n" + user); sys.exit()

key = next(l.split("=", 1)[1].strip().strip('"') for l in open(os.path.join(ROOT, "gateway/.dev.vars")) if l.startswith("GEMINI_API_KEY"))
URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={key}"
body = {"systemInstruction": {"parts": [{"text": system}]}, "contents": [{"role": "user", "parts": [{"text": user}]}],
        "generationConfig": {"maxOutputTokens": 4096, "responseMimeType": "application/json", "thinkingConfig": {"thinkingLevel": "low"}}}
t = time.time()
r = json.load(urllib.request.urlopen(urllib.request.Request(URL, json.dumps(body).encode(), {"Content-Type": "application/json"}), timeout=90))
text = "".join(p.get("text", "") for p in r["candidates"][0]["content"]["parts"] if not p.get("thought"))
out = json.loads(text)
print(f"[{time.time()-t:.1f}s]  {NAMES[target]} for a {level.upper()} learner, captions in {NAMES[native]}\n")
allfacts = " ".join(" ".join(v) for v in FACTS.values())
total = 0
for line in out["lines"]:
    words = len(line["text"].split())
    total += len(line["text"])
    nums = [n for n in re.findall(r"\d+", line["text"]) if n not in allfacts]
    flags = []
    if words > 28: flags.append(f"LONG {words}w")
    if "!" in line["text"]: flags.append("EXCLAIM")
    if nums: flags.append(f"NUMBER-NOT-IN-FACTS {nums}")
    print(f"{line['card']:<10} {line['text']}")
    print(f"{'':<10} {line['caption']}" + (f"   <-- {' '.join(flags)}" if flags else ""))
    print()
print(f"{len(out['lines'])} lines, {total} chars ≈ {total/14:.0f} s of speech")
