"""Strip the data out of the built page, leaving the shell the Worker serves.

The live console and the static snapshot are the SAME page — same base.html,
same merge_admin.py surgery, same charts. The only difference is where the
numbers come from: the snapshot has them baked in, the shell gets them
injected per request. Keeping one source is the point; a second copy of the
rendering code is how the two would drift into disagreeing about the same
day.

Writes admin/src/shell.html (committed — it holds no data, only the page).
"""
import re, pathlib, sys, os

HERE = pathlib.Path(__file__).resolve().parent
BUILD = pathlib.Path(os.environ.get("ADMIN_OUT", HERE / "build")) / "admin.html"
OUT = HERE.parent.parent / "admin" / "src" / "shell.html"

html = BUILD.read_text()

# 1) the data blob → a placeholder the Worker substitutes
html, n = re.subn(r"^const DATA = \{.*\};$",
                  "const DATA = __ADMIN_DATA__;", html, count=1, flags=re.M)
if n != 1:
    sys.exit("!! could not find the DATA literal — did merge_admin.py change?")

# 2) the as-of line says when it was READ, because now that is a live moment
old = ("document.getElementById('asof').textContent = "
       "`${fmtDate(DATA.windowStart)} ~ ${fmtDate(DATA.asOf)} · 프로덕션 DB에서 직접 집계`;")
new = ("document.getElementById('asof').textContent = "
       "`${fmtDate(DATA.windowStart)} ~ ${fmtDate(DATA.asOf)} · ` + (DATA.liveAt"
       " ? `${new Date(DATA.liveAt).toLocaleTimeString('ko-KR',"
       "{hour:'2-digit',minute:'2-digit'})} 조회 — 새로고침하면 다시 읽어요`"
       " : '프로덕션 DB에서 직접 집계');")
if old not in html:
    sys.exit("!! could not find the as-of line — did base.html change?")
html = html.replace(old, new)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(html)

# The shell is committed, so a leaked address or intro here would be a leak in
# git. Cheap guard: the built page's own emails must not survive the strip.
leaks = [w for w in re.findall(r"[\w.+-]+@[\w-]+\.[\w.]+", html)
         if not w.endswith(("@example.com",))]
if leaks:
    sys.exit(f"!! shell still contains addresses: {sorted(set(leaks))[:3]}")
print(f"wrote {OUT} ({len(html)} bytes, no data)", file=sys.stderr)
