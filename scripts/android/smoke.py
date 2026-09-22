#!/usr/bin/env python3
"""Flow smoke (master plan 1.5): walk the signed-in dev app through the main
loop on the emulator and stop at the first step that doesn't arrive.

    scripts/android/smoke.py            # app language must be Korean

Steps: launch → Talk home → open a call and hang up at once → Practice →
open a book → open the sentence deck and file one card → Progress.

The wrap-up is deliberately NOT walked: it needs a turn the learner SPOKE,
and the emulator's microphone is noise (a noisy "turn" would bill real
seconds and write a real summary). That step is on the device checklist (6).
The call is hung up before anyone speaks, so it bills nothing.
"""
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

PKG = "com.roro.futurevoice"
BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def adb(*args, check=False):
    return subprocess.run(["adb", *args], capture_output=True, text=True, check=check).stdout


def tree():
    adb("shell", "uiautomator", "dump", "/sdcard/smoke.xml")
    raw = adb("exec-out", "cat", "/sdcard/smoke.xml")
    try:
        return ET.fromstring(raw)
    except ET.ParseError:
        return ET.fromstring("<hierarchy/>")


def find(pred, timeout=20):
    end = time.time() + timeout
    while time.time() < end:
        for n in tree().iter("node"):
            if pred(n):
                return n
        time.sleep(1.5)
    return None


def text_is(*words):
    return lambda n: (n.get("text") or n.get("content-desc") or "").strip() in words


def text_has(word):
    return lambda n: word in (n.get("text") or "") or word in (n.get("content-desc") or "")


def tap(n):
    x1, y1, x2, y2 = map(int, BOUNDS.match(n.get("bounds")).groups())
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def crashed():
    return "FATAL EXCEPTION" in adb("logcat", "-d", "-b", "crash")


steps = []


def step(name, fn):
    ok, note = fn()
    if crashed():
        ok, note = False, "app crashed (logcat -b crash)"
    steps.append((name, ok, note))
    print(("✓" if ok else "✗"), name, "—", note)
    if not ok:
        report()
        sys.exit(1)


def report():
    passed = sum(1 for _, ok, _ in steps if ok)
    print(f"smoke: {passed}/{len(steps)} steps")


def launch():
    adb("shell", "am", "force-stop", PKG)
    adb("logcat", "-c")
    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    n = find(text_is("대화하기"), 40)
    return (n is not None, "Talk home with the call ring" if n is not None else "no call ring")


def call_and_hang_up():
    ring = find(text_is("대화하기"))
    if ring is None:
        return False, "no call ring"
    tap(ring)
    screen = find(lambda n: n.get("text") == "종료" or text_has("듣는 중")(n) or text_has("연결")(n), 30)
    if screen is None:
        return False, "call screen never appeared"
    time.sleep(2)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")   # hang up before anyone speaks
    back = find(text_is("대화하기"), 20)
    return (back is not None, "opened and hung up, back on home" if back is not None else "stuck after hanging up")


def open_tab(label, expect):
    def run():
        t = find(text_is(label))
        if t is None:
            return False, f"no {label} tab"
        tap(t)
        n = find(expect, 20)
        return (n is not None, f"{label} tab open" if n is not None else f"{label} tab empty")
    return run


def open_book():
    card = find(text_has("학습함"), 20)   # a book card's "N ago studied" line
    if card is None:
        return False, "no book card on the shelf"
    tap(card)
    page = find(lambda n: text_has("다시 듣기")(n) or text_has("이어서")(n) or text_has("점수")(n), 20)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    return (page is not None, "book page opened" if page is not None else "book page did not open")


def file_one_card():
    tile = find(text_has("문장"), 15)
    if tile is None:
        return True, "no sentence tile today (nothing due) — skipped"
    tap(tile)
    card = find(lambda n: text_has("눌러서")(n), 20)
    if card is None:
        return False, "deck did not open on a card"
    tap(card)
    time.sleep(1)
    known = find(lambda n: (n.get("content-desc") or "") in ("아는 것", "알아요"), 10)
    if known is None:
        return False, "no folder to file the card into"
    tap(known)
    time.sleep(2)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    return True, "revealed a card and filed it"


step("launch", launch)
step("call: open and hang up", call_and_hang_up)
step("Practice tab", open_tab("연습", text_is("학습 중")))
step("open a book", open_book)
step("deck: file one card", file_one_card)
step("Progress tab", open_tab("성장", lambda n: text_has("추정 레벨")(n) or text_has("레벨")(n)))
report()
