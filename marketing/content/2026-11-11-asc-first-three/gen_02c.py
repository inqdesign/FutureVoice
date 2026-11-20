# Shot 02, third try: one big pair per slip, the wrong words struck and the fixed words lit.
import sys
S="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc"
sys.argv=["x","ko",S+"/cap/en"]
import gen_lang as g
STYLE="""<style>
.bb{position:absolute;padding:44px 54px;border-radius:64px;font-family:-apple-system,'SF Pro Text',sans-serif;font-size:66px;line-height:1.32;font-weight:500;letter-spacing:-0.01em;max-width:1060px}
.me{right:70px;background:#D3E2FD;color:#111}
.fl{left:70px;background:#F2F2F7;color:#111}
.bb s{color:#E5484D;text-decoration-thickness:6px;text-decoration-color:#E5484D}
.bb b{color:#0A5CF5;font-weight:700}
.tag{position:absolute;font-size:46px;font-weight:800}
.tag span{font-weight:600;opacity:.6;margin-left:14px;font-size:40px}
</style>"""
def page(blue):
    fg="#fff" if blue else "#111"
    sh="0 40px 100px rgba(0,0,30,.28)" if blue else "0 30px 80px rgba(0,0,0,.10)"
    t=g.C["s02"]
    head=(f'<h1 style="top:200px;font-size:122px;color:{fg}">{t[0]}<br><i style="color:{"rgba(255,255,255,.62)" if blue else "#A3A3A8"}">{t[1]}</i></h1>'
          f'<p style="top:530px;color:{"rgba(255,255,255,.8)" if blue else "#6E6E73"}">{g.C["s02sub"]}</p>')
    bg=f'<div style="position:absolute;inset:0;background:{"#0A5CF5" if blue else "linear-gradient(#F1F1F3,#E4E4E8)"}"></div>'
    body=(bg+head+STYLE
      +f'<div class="tag" style="right:80px;top:820px;color:{fg}">지금의 나<span>틀리면서</span></div>'
      +f'<div class="bb me" style="top:910px;box-shadow:{sh}">Yesterday I <s>go</s> to the office early, so I <s>leave</s> at four.</div>'
      +f'<div class="tag" style="left:80px;top:1320px;color:{fg}">유창한 나<span>내 목소리로</span></div>'
      +f'<div class="bb fl" style="top:1410px;box-shadow:{sh}">Oh, so you <b>went</b> in early yesterday and <b>left</b> at four? Nice!</div>'
      +f'<div class="bb me" style="top:1880px;box-shadow:{sh}">I <s>am live</s> in Seoul <s>since</s> three years.</div>'
      +f'<div class="bb fl" style="top:2200px;box-shadow:{sh}">Right, <b>you\'ve been living</b> in Seoul <b>for</b> three years now.</div>')
    return body
g.render(page(True),f"{g.OUT}/out/02E_blue.png"); g.render(page(False),f"{g.OUT}/out/02E_grey.png")
from PIL import Image
a=Image.open(f"{g.OUT}/out/02E_blue.png").convert("RGB").resize((660,1434)); b=Image.open(f"{g.OUT}/out/02E_grey.png").convert("RGB").resize((660,1434))
s=Image.new("RGB",(1340,1434),"#fff"); s.paste(a,(0,0)); s.paste(b,(680,0)); s.save(f"{g.OUT}/out/02E.jpg",quality=88)
