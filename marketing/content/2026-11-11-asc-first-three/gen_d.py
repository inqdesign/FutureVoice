# D: soft grey, two-tone bold sans (after the founder's reference, 2026-11-11)
import gen, os
from gen import k, phone, crop, card, render
OUT=os.path.dirname(os.path.abspath(__file__))
gen.S="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc"
ICON="file:///Users/eunggyuelee/FutureVoice/FutureVoice/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
CSS="""body{background:linear-gradient(#F1F1F3,#E6E6E9);color:#111}
h1{position:absolute;left:0;right:0;text-align:center;font-weight:800;font-size:150px;line-height:1.2;letter-spacing:-6px}
h1 i{font-style:normal;color:#A3A3A8}
h1.l{text-align:left;left:100px}
p{position:absolute;font-size:58px;line-height:1.4;font-weight:500;letter-spacing:-1.5px}
.ph{background:linear-gradient(120deg,#C9CBD0,#F4F4F6 40%,#B9BBC1);box-shadow:0 0 0 4px #A9ABB1 inset,0 40px 120px rgba(0,0,0,.12)}
.fade{position:absolute;left:0;right:0;bottom:0;height:260px;background:linear-gradient(rgba(230,230,233,0),#E6E6E9 85%)}
.icon{position:absolute;border-radius:23%;overflow:hidden;box-shadow:0 50px 90px rgba(0,0,0,.28),0 0 0 22px #fff}
.icon img{width:100%;display:block}
.card{border-radius:56px;background:#fff;box-shadow:0 6px 30px rgba(0,0,0,.05)}
.face{border-radius:50%;box-shadow:0 30px 90px rgba(0,0,0,.14)}
.tile{position:absolute;left:100px;top:230px;width:210px;height:210px;border-radius:50px;background:#0A5CF5;display:grid;place-items:center}
"""
D1=('<h1 style="top:250px">유창해진 나와<br><i>매일 통화</i></h1>'
    + phone(k("nw-home-home"),150,900,1020)
    + f'<div class="icon" style="left:505px;top:760px;width:310px;height:310px"><img src="{ICON}"></div>'
    + '<div class="fade"></div>')
D2=('<h1 style="top:420px;font-size:136px">오늘 할 일은<br><i style="font-size:230px;letter-spacing:-10px">튜터가</i></h1>'
    + crop(k("nw-tutorbot-bubble"),321,715,60,60,440,1010,440,cls="face")
    + card(k("nw-tutorbot-note"),22,364,360,160,90,1400,1140,pad=44,extra="border-radius:80px;box-shadow:0 0 0 22px rgba(255,255,255,.55),0 30px 80px rgba(0,0,0,.08)")
    + '<p style="left:0;right:0;top:2120px;text-align:center;color:#222">루틴과 목표를 보고<br>지금 할 것 하나를 골라줘요.<br>궁금한 건 그냥 물어보세요.</p>')
ROW=k("nw-bookpage-drill")
D3=('<div class="tile"><svg width="120" height="120" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12.5l5 5L20 6.5"/></svg></div>'
    '<h1 class="l" style="top:500px">틀린 말은<br>전부 고쳐서 남겨요</h1>'
    '<p style="left:104px;right:90px;top:900px;color:#6E6E73">통화에서 틀린 문장이 고친 문장과 함께<br>교재가 돼요. 복습은 소리 내서 해요.</p>'
    + card(ROW,60,206,322,108,90,1240,1140,pad=40)
    + card(ROW,60,324,322,112,90,1740,1140,pad=40)
    + card(ROW,60,444,322,66,90,2254,1140,pad=40)
    + '<div class="fade" style="height:160px"></div>')
for i,b in enumerate([D1,D2,D3],1): render(b,CSS,f"{OUT}/D-soft/D{i}.png")
from PIL import Image
im=Image.new("RGB",(1320*3+80,2868),"#fff")
for i in range(3): im.paste(Image.open(f"{OUT}/D-soft/D{i+1}.png").convert("RGB"),(i*1360,0))
im.resize((im.width//3,im.height//3)).save(f"{OUT}/D_sheet.jpg",quality=88)
