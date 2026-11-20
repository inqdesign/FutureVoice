#!/usr/bin/env python3
"""Sample episodes of the podcast's GUEST segment, made to be heard by ear.

The founder's idea (2026-11-08): the hosts invite people who learn a language
for all kinds of reasons, and the guest's story is the episode. Every guest
comes from a different walk of life (family, work, sport, health, love,
faith, a move abroad...), so the segment can visit any field while staying
about the one thing every listener shares: learning a language. It sits in
the life show (life-show-probe.py, Layla and Kyle with lives) as one segment
among others, not the whole show.

The guests are CHARACTERS, like the hosts: invented, never presented as a
real person, and they name no real company, club or school. Nothing is
published; the daily news job is untouched.

    python3 scripts/guest-show-probe.py
    OUT_DIR=... python3 scripts/guest-show-probe.py

Reuses news-show-probe.py's Gemini, Cartesia and audio helpers so the voices,
pace and gaps are the show's own. Guests speak with the two other English
preset voices (Evie, Toby: British), so three people never share a voice.
"""
import concurrent.futures as cf
import datetime
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


show = load("show", "news-show-probe.py")
life = load("life", "life-show-probe.py")

TODAY = datetime.date.today().isoformat()
OUT = os.environ.get("OUT_DIR", os.path.expanduser(f"~/nawana-podcast/samples/guest-show-{TODAY}"))
LEVEL = "B1"
(A, _), (B, _) = show.HOSTS["en"]
GUEST_VOICE = {"F": "e5d4c33a-d8f6-46e8-a10f-b5afecc35648",   # Evie (F, GB)
               "M": "3d5ce2fb-e56c-42f0-9ed9-4662484063b4"}   # Toby (M, GB)

SEGMENT = "Why I'm Learning"

# Made-up messages from the audience. Narrower than the news show's filter:
# the closing question is addressed to "you listening", which is fine here.
INVENTED_VOICES = re.compile(r"\b(wrote (in|to us)|messaged us|caller|a listener (wrote|sent|asked))\b", re.I)

EPISODES = [
    {
        "slug": "01-grace-korean",
        "guest": "Grace",
        "language": "Korean",
        "voice": "F",
        "who": (
            "Grace, 63, a retired primary school teacher from Leeds, England. Started learning "
            "Korean at 61. Two reasons that grew into each other: her son married a Korean woman "
            "and her grandson (now 4) is growing up with Korean at home, and she wants to be "
            "able to talk with her daughter-in-law's parents, who speak no English; and during a "
            "long lonely winter after retiring she started watching Korean dramas. She studies "
            "with flashcards at the kitchen table every morning, and a weekly online class with "
            "people a third her age. Story: the first video call where she spoke Korean to her "
            "daughter-in-law's mother, she was so nervous she said 'goodbye' at the start; the "
            "mother laughed and cried, and now they talk every Sunday in slow, broken Korean "
            "and English. Honest about memory being slower at her age, and about it not "
            "mattering."),
        "thread": (
            f"{A}, who is learning Korean in Seoul and sometimes thinks she is 'too old' at 31, "
            "is moved and a bit embarrassed by that; it is the heart of the episode. She tells "
            "Grace, in English, the one Korean sentence she manages at her cafe every morning "
            "and how it feels."),
    },
    {
        "slug": "02-tom-spanish",
        "guest": "Tom",
        "language": "Spanish",
        "voice": "M",
        "who": (
            "Tom, 29, a sports physiotherapist from Bristol, England, who took a job with a "
            "football club in Valencia, Spain (never name the club) a year and a half ago, with "
            "almost no Spanish. Learned it on the job: the players, the kitchen staff, the "
            "physio room. Body-part words came first, then jokes. Story: in his first month he "
            "told a player to 'relax his embarrassment' instead of his knee because two words "
            "sounded alike to him (keep it to the idea, not a Spanish lesson); the whole "
            "dressing room still calls him by a nickname from it. Turning point: a young "
            "player from a small town, homesick, talked to him for an hour after an injury, "
            "and Tom understood almost all of it. Learning a language for work meant learning "
            "people, not words."),
        "thread": (
            f"{B}, the cook who learned Japanese in a kitchen in Japan, recognises the 'you "
            "learn it where you work' feeling and they compare kitchen talk and dressing-room "
            "talk."),
    },
    {
        "slug": "03-sophie-sign",
        "guest": "Sophie",
        "language": "Sign Language",
        "voice": "F",
        "who": (
            "Sophie, 36, an accountant from Brighton, England, learning British Sign Language "
            "(BSL) because her daughter Ivy, now 3, was born deaf. Started the week of the "
            "diagnosis, scared and with no idea where to begin; now the whole family signs at "
            "dinner, her husband and Ivy's big brother too. BSL has its own grammar and is a "
            "real language, not English with hands; say this simply and once. Story: Ivy's "
            "first signed sentence to her, at two, was 'mummy, more biscuit', and Sophie cried "
            "in the supermarket. Hard part: she is a beginner in a language her own child will "
            "soon be better at than her, and she has made peace with that. She describes signs "
            "in words, because the listener can't see them."),
        "thread": (
            "Both hosts are quiet and curious here; this is the one where the reason to learn "
            "is love, plainly. Keep it warm, never pitying; Ivy is a happy, funny kid."),
    },
]


def write_script(ep, earlier, used):
    G = ep["guest"]
    system = (
        f"Write one episode of the nawana Podcast, a warm, relaxed podcast for people learning "
        f"English at level {LEVEL}. Two hosts, {A} and {B}, and one guest, {G}. Everything in "
        "English.\n\n"
        "WHAT THE SEGMENT IS\n"
        f"- Segment \"{SEGMENT}\": the hosts invite someone who is learning a language, and "
        "their reason, and their story, is the episode. People learn languages for every "
        "reason there is, and each guest comes from a different part of life. The listener "
        "should hear someone a lot like them, finish a little braver, and want to tell their "
        "own reason out loud.\n"
        f"- Say the show's name and the segment once in the opening; {A} welcomes {G} and says "
        "in one plain sentence who they are.\n"
        "- Never a lecture, never \"don't give up!\" slogans: the encouragement is the guest's "
        "true-sounding story. No language-learning tips list. At most ONE thing the guest does "
        "that a listener could copy, said as what they do, not as advice.\n\n"
        "THE HOSTS (fixed; never contradict this)\n" + life.BIBLE + "\n\n"
        f"THE GUEST\n{ep['who']}\n"
        f"- {G} is a character, like the hosts. Give {G} small everyday detail that fits the "
        "above, never a big new life event. Never name a real company, club, school, app or "
        "programme; say what kind of place it is. No invented figures or statistics about the "
        "world.\n\n"
        f"- Each person's past is their own. Only {B} lived in Japan and works as a cook; only "
        f"{A} lives in Seoul. {G} never tells a host's story as their own, and the hosts never "
        f"tell {G}'s.\n\n"
        f"THIS EPISODE'S THREAD WITH THE HOSTS\n{ep['thread']}\n\n"
        + ("EARLIER EPISODES (keep continuity; refer back naturally in a line or two, don't "
           "recap)\n" + "\n".join(f"- {e}" for e in earlier) + "\n\n" if earlier else "")
        + "SHAPE\n"
        "- 850-950 words in total (about 7 minutes), 36-46 turns. "
        f"{G} talks the most (about half the words); the hosts ask, react and add short "
        "stories of their own. Not a strict rotation: follow the conversation.\n"
        "- Arc: why they started → the hardest or funniest moment (a real-feeling story with "
        "detail) → what changed for them → the one thing they do → what they'd say to someone "
        "who is where they were.\n"
        "- ONE phrase of the day: a reusable English chunk that comes out of the story (like "
        "\"I didn't have a clue\", \"it clicked\"). A host notices it once, says in simple "
        "words what it means, and it comes back naturally 3-4 times in all.\n"
        f"- Close: the hosts thank {G}, then one gentle question to the listener (why are YOU "
        "learning?), something they could answer out loud, then a short goodbye.\n"
        "- It is SPOKEN, the way people actually talk: contractions always, short reactions "
        "(Really? / Oh no. / I love that.), follow-up questions, laughing at themselves, a "
        "host rephrasing a harder word in simpler words now and then.\n"
        "- NOBODY else speaks: no listener messages, callers or comments.\n\n"
        f"LEVEL {LEVEL}\n"
        "- Everyday vocabulary and clear sentence shapes; no idiom stacking. Easier words, "
        "not a thinner conversation.\n"
        "- The voices are English voices. Never write words of another language (no "
        "romanization either): tell what was said in English (\"I said goodbye in Korean\"). "
        "The one exception is a language's own name.\n\n"
        "PUNCTUATION IS THE BREATH\n"
        "- A period ends a finished thought, a comma only where the voice should hang. No "
        "dashes between clauses, no ellipses, no emoji, no stage directions, no sound effects.\n\n"
        "Return STRICT JSON only:\n"
        '{ "title": "...", "phrase_of_the_day": "...", "summary": "...", '
        '"lines": [ { "speaker": "' + A + '", "text": "..." } ] }\n'
        f"- speaker is exactly one of \"{A}\", \"{B}\", \"{G}\".\n"
        f"- title: 8 words or fewer, true to the story: {G} is learning {ep['language']}.\n"
        + (f"- phrase_of_the_day must differ from earlier episodes': {', '.join(used)}.\n"
           if used else "")
        + "- summary: two sentences of what happened in the hosts' lives this episode and who "
        "came on, for continuity in later episodes."
    )
    best, best_score, note = None, None, ""
    for _ in range(4):
        script = show.gemini(system, "Write the episode." + note, max_tokens=14000)
        lines = script.get("lines", [])
        said = " ".join(l["text"] for l in lines)
        words = len(said.split())
        guest_words = sum(len(l["text"].split()) for l in lines if l.get("speaker") == G)
        stiff = len(life.STIFF.findall(said))
        guest_said = " ".join(l["text"] for l in lines if l.get("speaker") == G)
        phrase = (script.get("phrase_of_the_day") or "").strip().lower()
        ok = bool(lines) and all(l.get("speaker") in (A, B, G) for l in lines) \
            and not INVENTED_VOICES.search(said) \
            and "japan" not in guest_said.lower() \
            and ep["language"].split()[0].lower() in (script.get("title") or "").lower() + " " \
            and phrase not in used
        share = guest_words / words if words else 0
        score = (ok, stiff <= 4, words >= 800, 0.38 <= share <= 0.62, -stiff, words)
        if best is None or score > best_score:
            best, best_score = script, score
        if all(score[:4]):
            return script
        note = (f"\n\nYOUR LAST DRAFT FAILED: {words} words (needs 850-950), {G} had "
                f"{share:.0%} of them (needs about half), {stiff} uncontracted forms like "
                "\"I am\", \"do not\", \"it is\". Write it again: contract everywhere a native "
                "speaker would, give the guest the room, and make it long enough.")
    return best


def voice(script, folder, guest, guest_voice):
    voices = dict(show.HOSTS["en"])
    voices[guest] = guest_voice
    pieces = [(i, l["speaker"], s) for i, l in enumerate(script["lines"])
              for s in show.sentences(l["text"])]
    with cf.ThreadPoolExecutor(4) as pool:
        clips = list(pool.map(
            lambda p: show.trim(show.tts_pcm(voices[p[1]], p[2], "en")), pieces))
    line_pcm = [bytearray() for _ in script["lines"]]
    for (i, _, _), clip in zip(pieces, clips):
        if line_pcm[i]:
            line_pcm[i] += show.silence(show.SENTENCE_GAP)
        line_pcm[i] += clip
    episode = bytearray(show.silence(0.4))
    for i, pcm in enumerate(line_pcm):
        if i:
            episode += show.silence(show.TURN_GAP)
        episode += pcm
    episode += show.silence(0.8)
    show.to_mp3(bytes(episode), os.path.join(folder, "episode.mp3"), "128k")
    return len(episode) / 2 / show.SAMPLE_RATE, sum(len(p[2]) for p in pieces)


def main():
    if os.path.exists(OUT) and os.listdir(OUT):
        sys.exit(f"{OUT} already has files; set OUT_DIR to another folder")
    earlier, used, total = [], [], 0
    for ep in EPISODES:
        folder = os.path.join(OUT, ep["slug"])
        os.makedirs(folder, exist_ok=True)
        script = write_script(ep, earlier, used)
        used.append((script.get("phrase_of_the_day") or "").strip().lower())
        seconds, chars = voice(script, folder, ep["guest"], GUEST_VOICE[ep["voice"]])
        total += chars
        earlier.append(f"{SEGMENT} with {ep['guest']}: {script.get('summary', '')}")
        script.update({"segment": SEGMENT, "guest": ep["guest"]})
        json.dump(script, open(os.path.join(folder, "script.json"), "w"), ensure_ascii=False, indent=2)
        with open(os.path.join(folder, "script.txt"), "w") as f:
            f.write(f"{SEGMENT} · {script.get('title', '')}\n")
            f.write(f"Phrase of the day: {script.get('phrase_of_the_day', '')}\n\n")
            f.write("\n".join(f"{l['speaker']}: {l['text']}" for l in script["lines"]))
        lines = script["lines"]
        words = sum(len(l["text"].split()) for l in lines)
        gw = sum(len(l["text"].split()) for l in lines if l["speaker"] == ep["guest"])
        print(f"{ep['slug']}: {script.get('title')}  {int(seconds) // 60}:{int(seconds) % 60:02d}  "
              f"{words} words (guest {gw * 100 // max(words, 1)}%)  "
              f"${chars * show.USD_PER_CHAR:.2f}", flush=True)
    print(f"TTS total ≈ ${total * show.USD_PER_CHAR:.2f}  →  {OUT}")


if __name__ == "__main__":
    main()
