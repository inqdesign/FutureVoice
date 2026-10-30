#!/usr/bin/env python3
"""Proposed store metadata per locale, checked against Apple's limits and the live text."""
import json, os

ROOT = "/Users/eunggyuelee/FutureVoice/fastlane/metadata"
FOLDER = {"en-US": "en-US", "ko": "ko", "ja": "ja", "de-DE": "de-DE", "fr-FR": "fr-FR",
          "es-ES": "es-ES", "es-MX": "es-MX", "zh-Hant": "zh-Hant", "zh-Hans": "zh-Hans"}

P = {
 "en-US": dict(
  name="nawana: AI Speaking Practice",
  subtitle="Talk to your fluent self",
  keywords="spanish,japanese,korean,german,french,conversation,tutor,shadowing,pronunciation,accent,fluency,chat",
  promo="Your first 20 minutes are free. Call the fluent you, in your own voice, and every call turns into your own review book: words, phrases and the lines you fixed.",
  why="'Language Learning' is the most crowded term in Education and nawana can't rank for it. 'Speaking practice' and 'AI' are what people type when they want to TALK, which is the product. Subtitle moves the hook (your fluent self) up front."),
 "ko": dict(
  name="나와나: 내 목소리 AI 영어회화",
  subtitle="전화영어처럼 매일, 스피킹 연습",
  keywords="화상영어,AI영어,영어스피킹,오픽,토익스피킹,쉐도잉,섀도잉,프리토킹,발음교정,영어면접,영어발표,일본어회화,JLPT,스페인어,독일어,중국어,프랑스어,말하기,영어공부,원어민,튜터",
  promo="첫 20분은 무료예요. 내 목소리 그대로 유창해진 나와 통화하고, 끊으면 내가 한 말로 나만의 복습 교재가 만들어져요.",
  why="'언어학습'은 거의 검색되지 않고, 한국에서 사람들이 치는 말은 '영어회화'·'AI 영어'·'전화영어'예요. 이름에 영어회화를, 부제에 전화영어·스피킹을 올렸어요. 키워드에선 이름·부제와 겹치는 단어를 빼고 영어면접·영어발표를 넣었어요."),
 "ja": dict(
  name="nawana: AI英会話・スピーキング",
  subtitle="自分の声で、流暢な自分と毎日通話",
  keywords="英語,韓国語,外国語,ドイツ語,スペイン語,中国語,フランス語,電話,発音,シャドーイング,瞬間英作文,独り言,音読,英単語,語学,発話,オンライン英会話,ネイティブ,面接,TOEIC",
  promo="最初の20分は無料。自分の声のまま、流暢になった自分と通話できます。通話のあとは、話した内容がそのまま自分だけの復習教材に。",
  why="「英会話」「AI」「スピーキング」を名前に入れて、検索でいちばん重い欄を使います。キーワードは名前と重なる語を外し、面接・TOEICを足しました。"),
 "de-DE": dict(
  name="nawana: Englisch sprechen KI",
  subtitle="Übe mit deiner eigenen Stimme",
  keywords="lernen,Konversation,Aussprache,Business,Vokabeln,Sprachpartner,Tutor,Bewerbung,Shadowing,Spanisch",
  promo="Die ersten 20 Minuten sind gratis. Ruf dein fließendes Ich an, mit deiner eigenen Stimme. Jedes Gespräch wird zu deinem Lernbuch.",
  why="Deutsche suchen 'Englisch sprechen' und 'Englisch lernen'. 'Sprechen üben' allein sagt nicht, welche Sprache. 'Bewerbung' und 'Business' passen zur Zielgruppe (Englisch für den Job)."),
 "fr-FR": dict(
  name="nawana : parler anglais IA",
  subtitle="Entraîne-toi avec ta voix",
  keywords="apprendre,conversation,prononciation,oral,accent,entretien,vocabulaire,tuteur,shadowing,espagnol",
  promo="Les 20 premières minutes sont offertes. Appelle ton moi fluide, avec ta propre voix. Chaque appel devient ton carnet de révision.",
  why="« parler anglais » est la recherche principale, absente du nom actuel. « accent » et « oral » visent les francophones qui comprennent mais bloquent à l’oral."),
 "es-ES": dict(
  name="nawana: Hablar inglés con IA",
  subtitle="Practica con tu propia voz",
  keywords="aprender,conversación,pronunciación,speaking,vocabulario,entrevista,tutor,shadowing,alemán,japonés",
  promo="Los primeros 20 minutos son gratis. Llama a tu yo fluido, con tu propia voz. Cada llamada se convierte en tu cuaderno de repaso.",
  why="'Hablar inglés' es lo que se busca; el nombre actual no dice qué idioma. es-ES y es-MX llevaban textos idénticos: ahora cada uno usa sus 100 caracteres para cosas distintas."),
 "es-MX": dict(
  name="nawana: Hablar inglés con IA",
  subtitle="Practica con tu propia voz",
  keywords="ingles,aprender ingles,curso,conversacion,pronunciacion,speaking,toefl,examen,trabajo,entrevista",
  promo="Los primeros 20 minutos son gratis. Llama a tu yo fluido, con tu propia voz. Cada llamada se convierte en tu cuaderno de repaso.",
  why="es-MX también se indexa en la tienda de EE. UU. (según las herramientas de ASO; verifícalo en ASC). Sin tildes porque mucha gente las omite al buscar, y con 'trabajo', 'toefl', 'clases'."),
 "zh-Hant": dict(
  name="nawana: AI英文口說・英文會話",
  subtitle="用自己的聲音，每天練英文",
  keywords="英語,英檢,全民英檢,自學,日文,韓文,雅思,多益,托福,德文,西班牙文,法文,跟讀,發音,單字,聽力,面試,簡報,外語學習,家教,打電話,商務英文,旅遊英文",
  promo="前 20 分鐘免費。用你自己的聲音，和流利的自己通電話；掛掉之後，說過的話會整理成你專屬的複習教材。",
  why="台灣搜尋的是「英文口說」「英文會話」，放進名稱。關鍵字移除和名稱重複的字，加入面試、簡報、托福。"),
 "zh-Hans": dict(
  name="nawana: AI英语口语陪练",
  subtitle="用自己的声音，每天说英语",
  keywords="学英语,口语练习,英语对话,日语,韩语,雅思口语,托福,德语,西班牙语,法语,跟读,发音,纠音,听力,面试,外语学习,打电话,外教,商务英语,旅游英语,四六级,英语听力,自学",
  promo="前 20 分钟免费。用你自己的声音，和流利的自己打电话；挂断之后，说过的话会整理成你的专属复习教材。",
  why="名称直接用「英语口语陪练」，这是简体用户最常搜的说法。关键字去掉和名称重复的词，加入面试、托福。"),
}
LIM = {"name": 30, "subtitle": 30, "keywords": 100, "promo": 170}
FILE = {"name": "name.txt", "subtitle": "subtitle.txt", "keywords": "keywords.txt", "promo": "promotional_text.txt"}
out = {}
for loc, p in P.items():
    cur = {k: open(os.path.join(ROOT, FOLDER[loc], f)).read().strip() for k, f in FILE.items()}
    row = {"why": p["why"], "fields": {}}
    for k in LIM:
        n = len(p[k])
        if n > LIM[k]: print("OVER", loc, k, n)
        row["fields"][k] = {"now": cur[k], "now_len": len(cur[k]), "new": p[k], "new_len": n, "limit": LIM[k]}
    kws = p["keywords"].split(",")
    assert " " not in p["keywords"].replace("aprender ingles", "x"), loc
    dup = [w for w in kws if w.lower() in (p["name"] + " " + p["subtitle"]).lower() and len(w) > 1]
    row["dup_with_title"] = dup
    out[loc] = row
    print(loc, {k: f"{len(p[k])}/{LIM[k]}" for k in LIM}, "dup:", dup)
json.dump(out, open("meta.json", "w"), ensure_ascii=False, indent=1)
