"""The one place every prompt generator reads iOS from and writes Android to.

Every `scripts/android/gen-*.py` that lifts text out of the iOS Swift source
reads it at the SINGLE pinned ref (`scripts/android/promptgen/IOS_REF`), never
the worktree's copy of `FutureVoice/` (which is whatever iOS was when this
branch last merged it) and never a ref of its own. Re-pinning is one edit to
that file; every generator then follows.

    show(rel)          -> the Swift file at the ref
    emit(path, text)   -> write it, or with --check compare and fail if stale
    done()             -> exit 1 under --check when anything differed

`--ref <sha>` on any generator overrides the pin for a one-off look.
"""
import atexit, json, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PIN = ROOT / "scripts/android/promptgen/IOS_REF"

CHECK = "--check" in sys.argv
REF = PIN.read_text().strip()
if "--ref" in sys.argv:
    REF = sys.argv[sys.argv.index("--ref") + 1]
SHORT = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", REF],
                       check=True, capture_output=True, text=True).stdout.strip()

_stale = []


def show(rel: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), "show", f"{REF}:{rel}"],
                          check=True, capture_output=True, text=True).stdout


def emit(path, text: str, same=None) -> None:
    """`same(old, new)` overrides equality — only for a header line that
    names the ref (a server file's banner), never for prompt text."""
    path = pathlib.Path(path)
    rel = path.relative_to(ROOT)
    if CHECK:
        old = path.read_text() if path.exists() else None
        if old is None or not (same(old, text) if same else old == text):
            _stale.append(str(rel))
            print(f"✗ {rel} is not what iOS {SHORT} generates — run {pathlib.Path(sys.argv[0]).name}",
                  file=sys.stderr)
        else:
            print(f"✓ {rel} matches iOS {SHORT}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(f"wrote {rel} (iOS {SHORT})")


@atexit.register
def _finish():
    if _stale:
        # os._exit: sys.exit inside atexit can't change the status.
        import os
        sys.stderr.flush(); sys.stdout.flush()
        os._exit(1)


# --- reading Swift string literals -----------------------------------------

def unescape(s):
    out, k = "", 0
    while k < len(s):
        if s[k] == "\\":
            out += {"\"": "\"", "\\": "\\", "n": "\n", "t": "\t"}[s[k + 1]]
            k += 2
        else:
            out += s[k]; k += 1
    return out


def literal_at(src, anchor, start=0):
    """The Swift multiline literal opening on the first `\"\"\"` at/after
    `anchor`, as segments ('t', text) / ('i', expr), with Swift's semantics:
    closing-delimiter indent stripped, `\\` at a line end joins the next line
    (whose remaining indent is kept)."""
    i = src.find(anchor, start)
    if i < 0: sys.exit(f"anchor not found: {anchor!r}")
    o = src.find('"""', i)
    body_start = src.find("\n", o) + 1
    close = re.compile(r'\n([ \t]*)"""').search(src, body_start - 1)
    raw = src[body_start:close.start() + 1]
    indent = close.group(1)
    out = []
    for ln in raw.split("\n")[:-1]:
        if ln.strip() == "": out.append("")
        elif ln.startswith(indent): out.append(ln[len(indent):])
        else: sys.exit(f"bad indent: {ln!r}")
    text = ""
    for n, ln in enumerate(out):
        last = n == len(out) - 1
        if ln.endswith("\\") and not ln.endswith("\\\\"):
            text += ln[:-1]
        else:
            text += ln + ("" if last else "\n")
    segs, buf, k = [], "", 0
    while k < len(text):
        c = text[k]
        if c == "\\":
            nxt = text[k + 1]
            if nxt == "(":
                depth, j, in_str = 1, k + 2, False
                while depth:
                    ch = text[j]
                    if ch == "\\" and in_str: j += 2; continue
                    if ch == '"': in_str = not in_str
                    elif not in_str and ch == "(": depth += 1
                    elif not in_str and ch == ")": depth -= 1
                    j += 1
                if buf: segs.append(("t", buf)); buf = ""
                segs.append(("i", text[k + 2:j - 1]))
                k = j
                continue
            buf += {"\"": "\"", "\\": "\\", "n": "\n", "t": "\t"}[nxt]
            k += 2
            continue
        buf += c
        k += 1
    if buf: segs.append(("t", buf))
    return segs


def kt(s):
    return json.dumps(s, ensure_ascii=False).replace("$", "\\$")


LIT = r'"((?:[^"\\]|\\.)*)"'



def literal_after(src, anchor, start=0):
    """`literal_at`, plus the offset just past the closing delimiter."""
    segs = literal_at(src, anchor, start)
    i = src.find(anchor, start)
    o = src.find('"""', i)
    body_start = src.find("\n", o) + 1
    close = re.compile(r'\n([ \t]*)"""').search(src, body_start - 1)
    return segs, close.end()


def kotlin(segs, interp, indent="        "):
    """Segments as a Kotlin expression: text as escaped string literals, each
    interpolation mapped through `interp` (an unmapped one fails the run, so a
    new piece of an iOS prompt can never be dropped silently)."""
    parts = []
    for kind, v in segs:
        if kind == "t":
            parts.append(kt(v))
        elif v in interp:
            parts.append(interp[v])
        else:
            sys.exit(f"unmapped interpolation in {pathlib.Path(sys.argv[0]).name}: {v}")
    return f" +\n{indent}".join(parts) if parts else '""'


def plain(segs):
    """A literal with no interpolation, as a Python string."""
    if any(k == "i" for k, _ in segs):
        sys.exit(f"{pathlib.Path(sys.argv[0]).name}: literal carries an interpolation: {segs}")
    return "".join(v for _, v in segs)
