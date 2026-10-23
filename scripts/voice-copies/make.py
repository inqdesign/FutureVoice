"""Owned copies of the Cartesia library voices people speak in (2026-10-23).

A library voice reading another language keeps its own accent, and Cartesia
won't take an accent on a voice we don't own. So each one is cloned once from
~12 s of itself in its own language (texts.json) and the copy speaks every
other language (supabase/functions/_shared/voice-copies.ts).

Inputs, in the working directory: voices.json ({library id: {lang, name}} —
every id in ProfileVoices.swift plus public_personas.voice_preset_id, with the
language Cartesia reports). Output: map.json, resumable. Then:
  python3 gen.py map.json ../../supabase/functions/_shared/voice-copies.ts ../../gateway/src/voice-copies.ts
Key: ~/keys/cartesia.txt.
"""
import json,os,urllib.request,uuid,sys,time
K=open(os.path.expanduser("~/keys/cartesia.txt")).read().strip()
H={"Authorization":f"Bearer {K}","Cartesia-Version":"2026-08-14","User-Agent":"fv"}
voices=json.load(open("voices.json")); texts=json.load(open("texts.json"))
mp=json.load(open("map.json")) if os.path.exists("map.json") else {}
def post(url,body,ctype):
    r=urllib.request.Request(url,data=body,headers={**H,"Content-Type":ctype},method="POST")
    return urllib.request.urlopen(r,timeout=120).read()
for vid,v in sorted(voices.items()):
    if vid in mp: continue
    lang=v["lang"]; t=texts[lang]
    try:
        wav=post("https://api.cartesia.ai/tts/bytes",json.dumps({"model_id":"sonic-3.6","transcript":t,"voice":{"mode":"id","id":vid},"language":lang,
          "output_format":{"container":"wav","encoding":"pcm_s16le","sample_rate":44100},"generation_config":{"emotion":"neutral"}}).encode(),"application/json")
        open(f"ref_{vid}.wav","wb").write(wav)
        b=uuid.uuid4().hex
        def form(l):
            parts=[]
            for k,val in (("name",f"copy-{v['name']}-{vid[:8]}"[:100]),("language",l)):
                parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{val}\r\n'.encode())
            parts.append(f'--{b}\r\nContent-Disposition: form-data; name="clip"; filename="ref.wav"\r\nContent-Type: audio/wav\r\n\r\n'.encode()+wav+b"\r\n")
            return b"".join(parts)+f"--{b}--\r\n".encode()
        try: c=json.loads(post("https://api.cartesia.ai/voices/clone",form(lang),f"multipart/form-data; boundary={b}"))
        except urllib.error.HTTPError as e:
            print("clone lang fail",vid,lang,e.code,e.read()[:150]); c=json.loads(post("https://api.cartesia.ai/voices/clone",form("en"),f"multipart/form-data; boundary={b}"))
        mp[vid]={"lang":lang,"copy":c["id"],"name":v["name"]}
        json.dump(mp,open("map.json","w"),ensure_ascii=False,indent=1)
        print("ok",vid,lang,v["name"],c["id"],flush=True)
    except urllib.error.HTTPError as e: print("FAIL",vid,lang,e.code,e.read()[:200],flush=True)
    except Exception as e: print("FAIL",vid,lang,e,flush=True)
print("done",len(mp))
