# Shot 02, fourth try (founder: the page is MEETING the fluent you, and why talking with it works):
# the real meet screen, and four reasons around it.
import sys
R="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc/raw3"
sys.argv=["x","ko",R]
import gen_lang as g
STYLE="""<style>html{background:#E4E4E8}
.pt{position:absolute;width:470px;padding:34px 38px;border-radius:44px;background:rgba(255,255,255,.92);
    box-shadow:0 24px 70px rgba(0,0,0,.12);-webkit-backdrop-filter:blur(20px)}
.pt small{display:block;font-size:34px;font-weight:700;color:#0A5CF5;margin-bottom:8px}
.pt div{font-size:50px;font-weight:800;line-height:1.22;color:#111;letter-spacing:-0.02em}
</style>"""
def pt(tag,text,x,y): return f'<div class="pt" style="left:{x}px;top:{y}px"><small>{tag}</small><div>{text}</div></div>'
body=(g.title(("유창해진 나를","만나요"))+STYLE
      +g.phone("voice-meet",170,700,980)
      +pt("쉐도잉","내 목소리라<br>그대로 따라 해요",30,1230)
      +pt("교정","틀린 말은<br>바로 고쳐 줘요",820,1640)
      +pt("안정감","상대가 나라서<br>창피하지 않아요",30,2050)
      +pt("목표","되고 싶은 내가<br>눈앞에 있어요",820,2420))
g.render(body,f"{g.OUT}/out/02F.png")
