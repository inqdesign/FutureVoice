#!/usr/bin/env python3
# Casting of Cartesia stock voices onto the curated Find-people personas
# (2026-10-12). Reads voices_<lang>.json (GET /voices?language=) and
# personas.json from $VOICES_DIR, renders one sample per person into OUT
# and writes casting.json, which the migration 20261012140000 was built from.
import json, os, re, urllib.request
D=os.environ.get('VOICES_DIR','.')+'/'
OUT='/Users/eunggyuelee/Desktop/beta audio/people-voices'
K=open(os.path.expanduser('~/keys/cartesia.txt')).read().strip()
pool={}
for l in ['en','de','ko','ja']:
    for x in json.load(open(D+f'voices_{l}.json'))['data']:
        pool.setdefault((x['name'].strip(), x.get('country')), x['id'])
# (language, display_name, occupation prefix) -> (voice name, country, why)
CAST={
 ('ko','간호사 수진'):('Hyerin','KR','따뜻하고 차분한 간호사'),
 ('ko','민정 선생님'):('Seoyun','KR','친절하게 설명하는 강사'),
 ('ko','어머님'):('Subin','KR','점잖고 조심스러운 어머니'),
 ('ko','영숙 아주머니'):('Jihyun','KR','느긋한 아래층 아주머니'),
 ('ko','지현 선배'):('Soojin','KR','편하게 말하는 회사 선배'),
 ('ko','박 사장님'):('Jaewon','KR','차분한 중년 공인중개사'),
 ('ko','타오'):('Ryeowook','KR','여유 있는 대학원 준비생'),
 ('ko','현우|클라이밍'):('Minho','KR','편한 동호회 친구'),
 ('ko','미선'):('Yuna','KR','밝은 집배원'),
 ('ko','보라'):('Minji','KR','또렷한 수의테크니션'),
 ('ko','순자'):('Haeun','KR','해녀'),
 ('ko','은영'):('Yeji','KR','게스트하우스 사장'),
 ('ko','하늘'):('Soyeon','KR','자신감 있는 서핑샵 사장'),
 ('ko','민규'):('Junho','KR','생선가게 사장'),
 ('ko','재원'):('Taehyun','KR','치킨집 사장'),
 ('ko','정훈'):('Jaewon','KR','기관사'),
 ('ko','종석'):('Taehyun','KR','편의점 점주'),
 ('ko','태오'):('Ryeowook','KR','웹툰 어시스턴트'),
 ('ko','현우|낚싯배'):('Junho','KR','낚싯배 선장'),
 ('de','Britta'):('Sabine','DE','bestimmte Teamleiterin'),
 ('de','Emine'):('Karin','DE','freundliche Berlinerin'),
 ('de','Frau Weber'):('Klara','DE','sanfte Erzieherin'),
 ('de','Herr Klein'):('Oskar','DE','gesetzter Vermieter'),
 ('de','Jonas|Nachbar'):('Nico','DE','lockerer Nachbar'),
 ('de','Marek'):('Thomas','DE','ernsthafter Elektriker'),
 ('de','Nguyen'):('Leander','DE','warmer Pflegeazubi'),
 ('de','Sofia'):('Jennifer','DE','zugewandte Ärztin'),
 ('de','Andrej'):('Andreas','DE','Nachtportier'),
 ('de','Ayşe'):('Rena','DE','energische Sanitäterin'),
 ('de','Bruno'):('Klaus','DE','pensionierter Lokführer'),
 ('de','Hanne'):('Lorelei','DE','ruhige Hebamme'),
 ('de','Jonas|Orgelbauer'):('Jonas','DE','Orgelbauer'),
 ('de','Katja'):('Alina','DE','Fernfahrerin'),
 ('de','Lena'):('Lena','DE','Meeresbiologin'),
 ('de','Mehmet'):('Christian','DE','Späti-Besitzer'),
 ('de','Resi'):('Leni','DE','Hüttenwirtin'),
 ('de','Svenja'):('Emi','DE','Kranführerin'),
 ('de','Timo'):('Lukas','DE','Fahrradkurier'),
 ('en','Amir'):('Walid','SA','Syrian pharmacist, warm'),
 ('en','Diego'):('Ricardo',None,'Latin American barista'),
 ('en','Frank'):('Austin','US','steady landlord'),
 ('en','Marta'):('Jo','US','data analyst, casual'),
 ('en','Michelle'):('Ariana','US','kind teacher'),
 ('en','Priya|Nurse'):('Sindhu','IN','British-Indian nurse'),
 ('en','Ravi'):('Rahul','IN','Bengaluru team lead'),
 ('en','Sarah'):('Evie','GB','Manchester recruiter'),
 ('en','Yuki'):('Ayako','JP','Japanese, new in Seattle'),
 ('en','Aoife'):('Julia','GB','Kerry farmer & DJ'),
 ('en','Bea'):('Connie','US','game tester'),
 ('en','Dae-ho'):('Minho','KR','Korean delivery driver'),
 ('en','Hiroshi'):('Kenji','JP','Japanese inspector'),
 ('en','Ingrid'):('Tamsin','NZ','glaciologist'),
 ('en','Kwame'):('Tristan','ZA','Accra collective founder'),
 ('en','Lucia'):('Gabriela','US','medical interpreter'),
 ('en','Marcus'):('Griffin','GB','retired tugboat captain'),
 ('en','Maya'):('Bronte','AU','surf hostel owner'),
 ('en','Nadia'):('Daniela',None,'air traffic controller'),
 ('en','Owen'):('Toby','GB','Welsh organ builder'),
 ('en','Priya|Structural'):('Divya','IN','engineer in Kerala'),
 ('en','Rafael'):('Ricardo',None,'Mexico City driver'),
 ('en','Samir'):('Sagar','IN','ship cook'),
 ('en','Sofia'):('Mariana','CO','pastry chef'),
 ('en','Tomás'):('Carlo','IT','paramedic'),
}
people=json.load(open(D+'personas.json'))
def key(p):
    for (l,k),v in CAST.items():
        if l!=p['language']: continue
        name,_,occ=k.partition('|')
        if p['display_name']==name and (not occ or (p['occupation'] or '').startswith(occ)): return (l,k)
os.makedirs(OUT, exist_ok=True)
done=set(); rows=[]
for p in people:
    k=key(p)
    if not k: print('UNCAST',p['language'],p['display_name']); continue
    vname,cc,why=CAST[k]; vid=pool.get((vname,cc))
    if not vid: print('NOVOICE',vname,cc); continue
    rows.append({'persona_id':p['id'],'language':p['language'],'person':p['display_name'],'voice':vname,'voice_id':vid,'active':p['is_active']})
    if k in done: continue
    done.add(k)
    intro=re.split(r'(?<=[.!?。])\s+|(?<=요\.)|(?<=다\.)', (p['intro'] or '').strip())
    text=' '.join(intro[:2])[:200]
    body=json.dumps({"model_id":"sonic-3.6","transcript":text,"voice":{"mode":"id","id":vid},"language":p['language'],
          "output_format":{"container":"mp3","sample_rate":44100,"bit_rate":128000},
          "generation_config":{"speed":1.17,"emotion":"neutral"}}).encode()
    r=urllib.request.Request("https://api.cartesia.ai/tts/bytes",data=body,headers={"X-API-Key":K,"Cartesia-Version":"2026-08-14","Content-Type":"application/json","User-Agent":"probe"})
    try: data=urllib.request.urlopen(r).read()
    except Exception as e: print('fail',k,e); continue
    safe=p['display_name'].replace(' ','')+('_'+k[1].split('|')[1] if '|' in k[1] else '')
    open(os.path.join(OUT,f"{p['language']}_{'활성_' if p['is_active'] else ''}{safe}_{vname}.mp3"),'wb').write(data)
json.dump(rows,open(D+'casting.json','w'),ensure_ascii=False,indent=1)
print('rows',len(rows),'samples',len(done))
