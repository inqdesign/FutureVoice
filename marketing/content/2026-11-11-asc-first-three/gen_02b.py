# Shot 02, second try: the line I said, and the same line from the fluent me, in my voice.
import sys
S="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc"
sys.argv=["x","ko",S+"/cap/en"]
import gen_lang as g
FIX=S+"/cap/en/pair.png"; AV=S+"/avatar600.jpg"
U1=(245,1014,1260,1231); F1=(60,1365,1125,1584); U2=(395,1718,1260,1935); F2=(60,2069,1086,2288)
K=1.12
def bubble(box,Y,right,shadow):
    x0,y0,x1,y1=box; w=(x1-x0)*K; h=(y1-y0)*K
    X=1320-70-w if right else 70
    return (f'<div style="position:absolute;left:{X}px;top:{Y}px;width:{w}px;height:{h}px;border-radius:{60*K}px;overflow:hidden;box-shadow:{shadow}">'
            f'<img src="file://{FIX}" style="position:absolute;width:{1320*K}px;left:{-x0*K}px;top:{-y0*K}px"></div>'), Y+h
def who(name,note,Y,right):
    return (f'<div style="position:absolute;top:{Y}px;{"right" if right else "left"}:70px;display:flex;align-items:center;gap:26px;flex-direction:{"row-reverse" if right else "row"}">'
            f'<div style="text-align:{"right" if right else "left"}"><div style="font-size:52px;font-weight:800;color:#111">{name}</div>'
            f'<div style="font-size:38px;font-weight:600;color:#8E8E93;margin-top:2px">{note}</div></div></div>')
SH_U="0 24px 60px rgba(0,0,0,.08)"; SH_F="0 30px 80px rgba(10,92,245,.16)"
y=880; body=g.title(g.C["s02"],size=122)+g.sub(g.C["s02sub"],530)
body+=who("지금의 나","더듬더듬, 틀리면서",y,True); y+=130
b,y=bubble(U1,y,True,SH_U); body+=b; y+=100
body+=who("유창한 나","내 목소리로, 바르게",y,False); y+=130
b,y=bubble(F1,y,False,SH_F); body+=b; y+=170
b,y=bubble(U2,y,True,SH_U); body+=b; y+=70
b,y=bubble(F2,y,False,SH_F); body+=b
g.render(body,f"{g.OUT}/out/02D.png"); print("bottom",y)
