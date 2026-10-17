-- The third speech challenge: nervous before speaking? Say you're excited.
--
-- One study, and the script says out loud what it can and cannot show:
--   * Brooks, "Get excited: Reappraising pre-performance anxiety as
--     excitement", Journal of Experimental Psychology: General 143(3)
--     (2014), doi:10.1037/a0035325. In the public-speaking experiment,
--     participants said "I am excited" or "I am calm" aloud just before a
--     short videotaped speech; independent raters judged the "excited"
--     speakers more confident and more persuasive. Reappraisal raised
--     felt excitement but did not take the anxiety away — the script says
--     so. Later work has not always reproduced the effect, which is the
--     script's caveat; it names no specific follow-up study.
--
-- Same shape as `20261015120000`: one row per target language, written in
-- each language rather than translated. German says "Ich freue mich darauf"
-- because "aufgeregt" means nervous AND excited — the script uses that.
-- Spanish quotes are gender-neutral («Mantengo la calma» / «¡Qué emoción!»)
-- and avoid vídeo/video.

insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds)
values
  ('5beec000-0000-4000-8000-00000000000b', 'en', 'Nervous? Say you''re excited', 'explainer',
   'Your heart is racing, your hands are cold, and you''re about to speak in front of people. Most of us tell ourselves the same thing: calm down. But what if that''s the wrong advice?

In 2014, Alison Wood Brooks, a researcher at Harvard Business School, put it to the test. She asked people to give a short speech in front of a camera. Right before they started, some said out loud, "I am calm." Others said, "I am excited."

Then other people watched the videos and rated them. The speakers who had said "I am excited" came across as more confident and more persuasive.

Why would one sentence make a difference? Being nervous and being excited feel almost the same in the body. Either way, your heart beats faster. Calming down is hard, but giving the same feeling a different name is easy.

There''s a catch, though. The nerves didn''t go away. People still felt anxious. And later studies haven''t always found the same effect, so this isn''t a magic trick.

But it costs nothing to try. Before you press record, say it once: I''m excited.',
   '["https://doi.org/10.1037/a0035325"]'::jsonb, 75),

  ('5beec000-0000-4000-8000-00000000000c', 'ko', '떨릴 땐 설렌다고 말해 보세요', 'explainer',
   '심장은 쿵쾅거리고, 손은 차갑고, 이제 곧 사람들 앞에서 말을 해야 합니다. 이럴 때 우리는 보통 스스로에게 이렇게 말하죠. 진정하자. 그런데 그게 틀린 조언이라면 어떨까요?

2014년, 하버드 경영대학원의 앨리슨 우드 브룩스가 이걸 실험해 봤습니다. 사람들에게 카메라 앞에서 짧은 연설을 하게 했는데요. 시작하기 직전에, 어떤 사람들은 "나는 차분하다"고 소리 내어 말했고, 다른 사람들은 "나는 설렌다"고 말했습니다.

그리고 그 영상을 다른 사람들이 보고 평가했습니다. "설렌다"고 말한 사람들이 더 자신감 있고, 더 설득력 있게 보였습니다.

말 한마디가 왜 차이를 만들까요? 긴장과 설렘은 몸으로 느끼기에 거의 같습니다. 어느 쪽이든 심장이 빨리 뛰니까요. 마음을 가라앉히기는 어렵지만, 같은 느낌에 다른 이름을 붙이는 건 쉽습니다.

다만 알아 둘 점이 있습니다. 긴장이 사라진 건 아니었습니다. 사람들은 여전히 떨렸습니다. 그리고 이후의 연구에서 늘 같은 결과가 나온 것도 아니라서, 마법 같은 비법은 아닙니다.

그래도 해 보는 데 드는 건 없죠. 녹화 버튼을 누르기 전에, 한 번 말해 보세요. 나는 설렌다.',
   '["https://doi.org/10.1037/a0035325"]'::jsonb, 75),

  ('5beec000-0000-4000-8000-00000000000d', 'ja', '緊張したら「ワクワクする」と言おう', 'explainer',
   '心臓がドキドキして、手が冷たくなる。これから人前で話さなければならない。そんなとき、たいていの人は自分にこう言い聞かせます。「落ち着こう」。でも、それが間違ったアドバイスだとしたら、どうでしょう。

2014年、ハーバード・ビジネス・スクールの研究者、アリソン・ウッド・ブルックスが、これを実験で確かめました。参加者に、カメラの前で短いスピーチをしてもらったのです。話し始める直前に、ある人たちは「私は落ち着いている」と声に出して言い、別の人たちは「私はワクワクしている」と言いました。

そのスピーチの動画を、ほかの人たちが見て評価しました。すると、「ワクワクしている」と言った人のほうが、自信があって、説得力があるように見えたのです。

なぜ、ひとことで違いが出るのでしょうか。緊張とワクワクは、体の感覚としてはほとんど同じです。どちらも心臓が速くなります。気持ちを静めるのは難しくても、同じ感覚に別の名前をつけるのは簡単です。

ただし、注意も必要です。緊張が消えたわけではありません。参加者は、やはり不安を感じていました。それに、その後の研究で、いつも同じ結果が出ているわけでもありません。魔法ではないのです。

でも、試すのにお金はかかりません。録画ボタンを押す前に、一度言ってみましょう。「ワクワクしている」。',
   '["https://doi.org/10.1037/a0035325"]'::jsonb, 75),

  ('5beec000-0000-4000-8000-00000000000e', 'de', 'Lampenfieber? Sagt: Ich freue mich darauf', 'explainer',
   'Das Herz rast, die Hände sind kalt, und gleich sollt ihr vor anderen sprechen. Die meisten sagen sich dann dasselbe: Bleib ruhig. Aber was, wenn genau das der falsche Rat ist?

2014 hat Alison Wood Brooks von der Harvard Business School das untersucht. Sie ließ Menschen vor einer Kamera eine kurze Rede halten. Kurz vor dem Start sagten manche laut: „Ich bin ruhig.“ Andere sagten: „Ich freue mich darauf.“

Danach haben sich andere die Videos angesehen und sie bewertet. Wer „Ich freue mich darauf“ gesagt hatte, wirkte selbstbewusster und überzeugender.

Warum macht ein einziger Satz einen Unterschied? Nervosität und Vorfreude fühlen sich im Körper fast gleich an. In beiden Fällen schlägt das Herz schneller. Im Deutschen gibt es dafür sogar nur ein Wort: aufgeregt. Sich zu beruhigen ist schwer. Demselben Gefühl einen anderen Namen zu geben, ist leicht.

Allerdings gibt es einen Haken. Die Nervosität war nicht weg. Die Leute waren immer noch angespannt. Und spätere Studien haben nicht immer dasselbe gefunden. Ein Zaubertrick ist das also nicht.

Aber ausprobieren kostet nichts. Bevor ihr auf Aufnahme drückt, sagt einmal laut: Ich freue mich darauf.',
   '["https://doi.org/10.1037/a0035325"]'::jsonb, 75),

  ('5beec000-0000-4000-8000-00000000000f', 'es', '¿Nervios? Di «¡Qué emoción!»', 'explainer',
   'El corazón te late a mil, tienes las manos frías y estás a punto de hablar delante de otras personas. Casi todos nos decimos lo mismo: cálmate. ¿Y si ese fuera justo el consejo equivocado?

En 2014, Alison Wood Brooks, investigadora de la Escuela de Negocios de Harvard, lo puso a prueba. Pidió a varias personas que dieran un discurso corto delante de una cámara. Justo antes de empezar, algunas dijeron en voz alta: «Mantengo la calma». Otras dijeron: «¡Qué emoción!».

Luego, otras personas vieron las grabaciones y las evaluaron. Quienes habían dicho «qué emoción» parecían más seguros y más convincentes.

¿Por qué una sola frase iba a cambiar algo? Los nervios y la emoción se sienten casi igual en el cuerpo. En los dos casos, el corazón se acelera. Calmarse es difícil, pero ponerle otro nombre a la misma sensación es fácil.

Eso sí, hay un detalle. Los nervios no desaparecieron. La gente seguía sintiéndose nerviosa. Y estudios posteriores no siempre han encontrado el mismo efecto, así que no es un truco de magia.

Pero probarlo no cuesta nada. Antes de darle a grabar, dilo una vez: «¡Qué emoción!».',
   '["https://doi.org/10.1037/a0035325"]'::jsonb, 75)
on conflict (id) do nothing;
