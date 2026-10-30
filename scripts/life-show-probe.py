#!/usr/bin/env python3
"""Sample episodes of a LIFE podcast, made by hand to be heard by ear.

The founder's idea (2026-10-22): the daily show as a real podcast people
listen to for comfort, about life, trying things, learning a language,
brands and songs, instead of the day's news. The two hosts get LIVES (a
fixed show bible) and episodes carry a thread from one to the next, which is
what makes a podcast something you come back to. This probe makes three
weekday samples (Mon Reset, Wed How It Started, Fri The Song) in order, each
told what the earlier ones said. Nothing is published; the daily news job
is untouched.

    python3 scripts/life-show-probe.py
    OUT_DIR=... python3 scripts/life-show-probe.py

Reuses news-show-probe.py's Gemini, Cartesia and audio helpers so the voices,
pace and gaps are the show's own.
"""
import concurrent.futures as cf
import datetime
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("show", os.path.join(HERE, "news-show-probe.py"))
show = importlib.util.module_from_spec(spec)
spec.loader.exec_module(show)

TODAY = datetime.date.today().isoformat()
OUT = os.environ.get("OUT_DIR", os.path.expanduser(f"~/Desktop/beta audio/life-show-samples-{TODAY}"))
LEVEL = "B1"
(A, _), (B, _) = show.HOSTS["en"]

# Who the hosts are. Fixed, so every episode tells the same two lives; the
# model may add small everyday detail but never contradict this.
BIBLE = f"""\
{A}: 31, American, moved to Seoul eight months ago for her partner's job. Works
remotely as a graphic designer. Learning Korean, around beginner-intermediate:
she can order food and make small talk, then freezes when people talk fast.
Feels shy speaking, sometimes thinks she is "too old" to get good, keeps going
anyway. Loves stationery, cafes and long walks along the Han River.
{B}: 34, American, lived in Japan for three years in his twenties teaching
English, learned Japanese the hard way (lots of embarrassing mistakes, a few he
still laughs about). Now back in Portland, works as a cook in a small
restaurant. Calm, curious, a good listener, the one who asks "and how did that
feel?". Plays guitar badly and happily.
They met years ago online, have done this show together for a while, and are
real friends. Neither is a teacher on the show: they are two people who know
what learning a language and living somewhere new feels like."""

EPISODES = [
    {
        "slug": "01-monday-reset",
        "segment": "Monday Reset",
        "brief": (
            "Small habits and starting the week again. Theme: the tiny-goal idea, a goal so "
            f"small you can't fail it. {A} admits last week went badly (she skipped her Korean "
            f"practice and felt guilty). {B} shares how in Japan he made one tiny rule that "
            f"saved him. By the end {A} sets ONE tiny goal for this week, out loud: say one "
            "sentence in Korean to a stranger every day, even just at a cafe. They agree to check "
            "on Friday."),
        "research": None,
    },
    {
        "slug": "02-how-it-started",
        "segment": "How It Started",
        "brief": (
            "The beginning of a brand people love: MUJI. How it started, what the founders "
            "believed, how small it began. The hosts connect it to their own lives (Seoul has "
            "MUJI stores; a cook's view of simple things) and to the idea that starting small "
            f"and plain is fine. A one-line callback early on: {B} asks how {A}'s tiny goal is "
            "going (two days in, one good day, one day she chickened out)."),
        "research": ("Search the web: the founding story of MUJI (Mujirushi Ryohin). When and "
                     "where it began, as part of which company, who was behind it (designer, "
                     "creative director), how many products it started with, what the name means, "
                     "the idea behind it ('no-brand quality goods', 'this is enough'), when the "
                     "first own store opened and when it went abroad. 10 plain, checked facts."),
    },
    {
        "slug": "03-the-song",
        "segment": "The Song",
        "brief": (
            "A song and the story behind it: 'Here Comes the Sun' by the Beatles. How and where "
            "it was written, what was going on in the songwriter's life. Then each host says when "
            f"a song got them through a hard stretch. It is Friday, so {B} checks on {A}'s tiny "
            "goal from Monday: she did it four days of five, and on one of them a cafe owner "
            "answered her and they had a real little chat. Celebrate it warmly, no lecture."),
        "research": ("Search the web: the story behind the Beatles song 'Here Comes the Sun'. Who "
                     "wrote it, when, where (whose garden), what he was avoiding that day, what "
                     "kind of time it was for him and the band, which album it is on and when it "
                     "came out, anything notable about how it has been received since. 10 plain, "
                     "checked facts."),
    },
]


def research(question):
    for _ in range(3):
        notes, grounding = show.gemini(None, question, search=True)
        if grounding["sources"]:
            break
    else:
        sys.exit("the model never searched")
    facts = show.gemini(
        "From the RESEARCH, list the facts that are clearly supported. Facts only from the "
        'RESEARCH, nothing added. Return JSON: { "facts": ["...", ...] }, 8-10 facts, each 25 '
        "words or fewer, plain English.",
        "RESEARCH:\n" + notes).get("facts", [])
    return facts, grounding["sources"]


def write_script(ep, facts, earlier):
    system = (
        f"Write one episode of the nawana Podcast, a warm, relaxed podcast for people learning "
        f"English at level {LEVEL}. Two hosts, {A} and {B}. Everything in English.\n\n"
        "WHAT THE SHOW IS\n"
        "- Not news. Two friends talking about life: small challenges, living somewhere new, "
        "learning a language, things they love. The listener should feel like they are sitting "
        "with friends, a little braver at the end. Warm, honest, sometimes funny. Never a "
        "lecture, never \"don't give up!\" slogans: encouragement comes from the hosts' own "
        "honest stories.\n"
        f"- This episode's segment: \"{ep['segment']}\". Say the show's name and the segment "
        "once in the opening.\n\n"
        "THE HOSTS (fixed; never contradict this)\n" + BIBLE + "\n"
        "- The hosts may tell small everyday stories from their own lives that fit these "
        "facts. That is the show.\n"
        "- NOBODY else is on the show: no listener messages, callers, guests, polls or "
        "comments. Never \"a listener wrote in\".\n\n"
        + ("EARLIER EPISODES (keep continuity; refer back naturally, don't recap)\n"
           + "\n".join(f"- {e}" for e in earlier) + "\n\n" if earlier else "")
        + "SHAPE\n"
        "- 750-850 words in total (about 6 minutes), 30-38 turns, alternating, "
        f"{A} first. Count: under 700 words is too short.\n"
        "- ONE phrase of the day: a reusable English chunk that fits the theme (like \"I've "
        "been meaning to\", \"take it one day at a time\"). A host notices it once, says in "
        "simple words what it means, and both use it again naturally later, 3-4 times in all.\n"
        "- Close with one gentle question to the listener, something they could answer out "
        "loud about their own life, then a short goodbye.\n"
        "- It is SPOKEN, the way two friends actually talk: contractions always, short "
        "reactions (Really? / Oh no. / I love that.), follow-up questions, laughing at "
        "themselves, a host rephrasing a harder word in simpler words now and then.\n"
        "- Vary the turns: some are two words, most are 2-3 sentences, a story can be 4.\n\n"
        f"LEVEL {LEVEL}\n"
        "- Everyday vocabulary and clear sentence shapes; no idiom stacking. Easier words, "
        "not a thinner conversation.\n\n"
        + ("FACTS\n- Every fact, name, date and number about the real brand or song comes "
           "from the FACTS below. Never invent a quote, a figure or a detail about real people "
           "or companies. Opinions and personal stories are the hosts' own.\n"
           "- Many listeners live in Korea and elsewhere; the first time a real person or "
           "place comes up, say in a few plain words who or what it is.\n\n" if facts else "")
        + "PUNCTUATION IS THE BREATH\n"
        "- A period ends a finished thought, a comma only where the voice should hang. No "
        "dashes between clauses, no ellipses, no emoji, no stage directions, no sound effects.\n\n"
        "Return STRICT JSON only:\n"
        '{ "title": "...", "phrase_of_the_day": "...", "summary": "...", '
        '"lines": [ { "speaker": "' + A + '", "text": "..." } ] }\n'
        "- title: 8 words or fewer.\n"
        "- summary: two sentences of what happened in the hosts' lives this episode, for "
        "continuity in later episodes."
    )
    user = "THIS EPISODE:\n" + ep["brief"]
    if facts:
        user += "\n\nFACTS:\n" + "\n".join(f"- {f}" for f in facts)
    # The first samples came back with not one contraction ("I am", "do not",
    # "let us") and 530-630 words, both asked for in the prompt. Spoken
    # English that never contracts reads as a textbook, so both are checked
    # here and the model is told what it got wrong.
    best, best_score, note = None, None, ""
    for _ in range(4):
        script = show.gemini(system, user + note, max_tokens=12000)
        said = " ".join(l["text"] for l in script.get("lines", []))
        words = len(said.split())
        stiff = len(STIFF.findall(said))
        ok = script.get("lines") and not show.INVENTED_VOICES.search(said)
        score = (bool(ok), stiff <= 4, words >= 720, -stiff, words)
        if best is None or score > best_score:
            best, best_score = script, score
        if ok and stiff <= 4 and words >= 720:
            return script
        note = (f"\n\nYOUR LAST DRAFT FAILED: it had {words} words (needs 750-850) and "
                f"{stiff} uncontracted forms like \"I am\", \"do not\", \"it is\", \"let us\". "
                "Write it again: contract everywhere a native speaker would (I'm, don't, it's, "
                "let's, that's, I've, we're), and make it long enough.")
    return best


STIFF = __import__("re").compile(
    r"\b(I am|you are|we are|they are|it is|that is|there is|do not|does not|"
    r"did not|is not|are not|was not|can not|cannot|will not|would not|let us|I will|"
    r"you will|I would)\b", __import__("re").I)


def voice(script, folder):
    voices = dict(show.HOSTS["en"])
    pieces = [(i, l["speaker"], s) for i, l in enumerate(script["lines"])
              for s in show.sentences(l["text"])]
    with cf.ThreadPoolExecutor(4) as pool:
        clips = list(pool.map(
            lambda p: show.trim(show.tts_pcm(voices.get(p[1], show.HOSTS["en"][0][1]), p[2], "en")),
            pieces))
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
    earlier, total = [], 0
    for ep in EPISODES:
        folder = os.path.join(OUT, ep["slug"])
        os.makedirs(folder, exist_ok=True)
        facts, sources = research(ep["research"]) if ep["research"] else ([], [])
        script = write_script(ep, facts, earlier)
        seconds, chars = voice(script, folder)
        total += chars
        earlier.append(f"{ep['segment']}: {script.get('summary', '')}")
        script.update({"segment": ep["segment"], "facts": facts, "sources": sources})
        json.dump(script, open(os.path.join(folder, "script.json"), "w"), ensure_ascii=False, indent=2)
        with open(os.path.join(folder, "script.txt"), "w") as f:
            f.write(f"{ep['segment']} · {script.get('title', '')}\n")
            f.write(f"Phrase of the day: {script.get('phrase_of_the_day', '')}\n\n")
            f.write("\n".join(f"{l['speaker']}: {l['text']}" for l in script["lines"]))
            if facts:
                f.write("\n\nFacts used:\n" + "\n".join(f"- {x}" for x in facts))
        words = sum(len(l["text"].split()) for l in script["lines"])
        print(f"{ep['slug']}: {script.get('title')}  {int(seconds) // 60}:{int(seconds) % 60:02d}  "
              f"{words} words  ${chars * show.USD_PER_CHAR:.2f}", flush=True)
    print(f"TTS total ≈ ${total * show.USD_PER_CHAR:.2f}  →  {OUT}")


if __name__ == "__main__":
    main()
