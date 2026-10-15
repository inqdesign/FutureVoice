-- The second speech challenge: does learning languages slow ageing?
--
-- Every claim in the script is from a published study, and the script says
-- out loud what those studies can and cannot show:
--   * Amoruso et al., Nature Aging 5(11):2340–54 (10 Nov 2025),
--     doi:10.1038/s43587-025-01000-2 — 86,149 adults aged 51–90 in 27
--     European countries; monolingualism linked to accelerated ageing
--     (OR 2.11, RR 1.43), dose-dependent across languages. Observational.
--     The script says "more likely", not "twice": "twice" is the odds ratio,
--     and read aloud it would mean the relative risk, which is 1.43.
--   * Bak et al., Annals of Neurology 75(6) (2014), doi:10.1002/ana.24158 —
--     Lothian Birth Cohort 1936, tested at 11 and again in their early 70s;
--     bilinguals did better than their childhood score predicted, including
--     those who learned the second language as adults.
--   * Berggren et al., Psychology and Aging 35(2) (2020) — 160 adults aged
--     65–75, 11 weeks of Italian vs relaxation training: no difference on
--     memory, working memory or intelligence.
--
-- Same shape as the first challenge (`20261010150000`): one row per target
-- language, written in each language rather than translated.

insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds)
values
  ('5beec000-0000-4000-8000-000000000005', 'en', 'Can languages keep you young?', 'explainer',
   'Have you ever heard that learning a language can slow down ageing? It sounds almost too good to be true, so let''s look at what the research actually says.

In 2025, a large study was published in the journal Nature Aging. Researchers looked at more than eighty-six thousand people, aged fifty-one to ninety, in twenty-seven European countries. People who spoke only one language were more likely to be ageing faster than expected. And the more languages people spoke, the lower that risk was.

There''s an important catch, though. A study like this shows a link, not a cause. People who speak several languages may be different in other ways, too.

So is it worth starting later in life? A study in Scotland found that people who learned a second language as adults also did better in old age than their childhood test scores predicted. But in a Swedish trial, older adults who took an eleven-week Italian course showed no change in their memory.

The honest answer is that we don''t know for sure yet. But a new language gives you a reason to talk to new people. And that can''t hurt.',
   '["https://doi.org/10.1038/s43587-025-01000-2", "https://doi.org/10.1002/ana.24158"]'::jsonb, 75),

  ('5beec000-0000-4000-8000-000000000006', 'ko', '언어 공부는 노화를 늦출까', 'explainer',
   '외국어를 배우면 덜 늙는다는 이야기, 들어 보셨나요? 듣기에는 참 좋은 말인데요, 연구가 실제로 뭐라고 하는지 한번 살펴보겠습니다.

2025년, 학술지 네이처 에이징에 큰 연구가 실렸습니다. 유럽 스물일곱 개 나라에서 쉰한 살부터 아흔 살까지, 팔만 육천 명이 넘는 사람들의 자료를 분석했는데요. 한 가지 언어만 쓰는 사람은 예상보다 빨리 늙고 있을 가능성이 더 높았습니다. 그리고 쓰는 언어가 많을수록 그 위험은 더 낮았습니다.

다만 꼭 알아 둘 점이 있습니다. 이런 연구는 관련이 있다는 걸 보여 줄 뿐, 원인을 증명하지는 못합니다. 여러 언어를 쓰는 사람들은 다른 면에서도 다를 수 있으니까요.

그럼 나이 들어 시작해도 의미가 있을까요? 스코틀랜드의 한 연구에서는 어른이 되어 제2 언어를 배운 사람들도, 노년에 어린 시절 점수로 예상한 것보다 더 좋은 결과를 보였습니다. 하지만 스웨덴의 한 실험에서는 십일 주 동안 이탈리아어를 배운 노인들의 기억력에 변화가 없었습니다.

솔직히 말하면, 아직 확실한 답은 없습니다. 그래도 새 언어는 새로운 사람과 이야기할 이유를 만들어 줍니다. 그게 나쁠 리는 없겠죠.',
   '["https://doi.org/10.1038/s43587-025-01000-2", "https://doi.org/10.1002/ana.24158"]'::jsonb, 75),

  ('5beec000-0000-4000-8000-000000000007', 'ja', '外国語で老けにくくなる？', 'explainer',
   '外国語を学ぶと、老けにくくなる。そんな話を聞いたことはありませんか。うれしい話ですが、研究は実際に何と言っているのでしょうか。

2025年、学術誌「ネイチャー・エイジング」に、大きな研究が発表されました。ヨーロッパの27か国で、51歳から90歳までの8万6千人以上のデータを分析したものです。一つの言語しか使わない人は、予想より早く老化が進んでいる可能性が高いという結果でした。そして、使う言語が多いほど、そのリスクは低くなっていました。

ただし、注意も必要です。この種の研究でわかるのは関連であって、原因ではありません。複数の言語を話す人は、ほかの面でも違いがあるかもしれないからです。

では、大人になってから始めても意味はあるのでしょうか。スコットランドの研究では、大人になってから第二言語を学んだ人も、子どもの頃のテストから予想されるより、高齢になってからの成績が良かったそうです。一方、スウェーデンの実験では、11週間イタリア語を学んだ高齢者の記憶力に、変化は見られませんでした。

正直に言うと、まだはっきりした答えはありません。でも、新しい言葉は、新しい人と話すきっかけをくれます。それが悪いはずはありませんよね。',
   '["https://doi.org/10.1038/s43587-025-01000-2", "https://doi.org/10.1002/ana.24158"]'::jsonb, 75),

  ('5beec000-0000-4000-8000-000000000008', 'de', 'Halten Sprachen jung?', 'explainer',
   'Habt ihr schon mal gehört, dass Sprachenlernen das Altern bremsen kann? Klingt fast zu schön, um wahr zu sein. Schauen wir uns also an, was die Forschung wirklich sagt.

2025 erschien in der Fachzeitschrift Nature Aging eine große Studie. Ausgewertet wurden Daten von über 86.000 Menschen zwischen 51 und 90 Jahren aus 27 europäischen Ländern. Wer nur eine Sprache sprach, alterte mit höherer Wahrscheinlichkeit schneller als erwartet. Und je mehr Sprachen jemand sprach, desto geringer war dieses Risiko.

Allerdings gibt es einen wichtigen Haken. Solche Studien zeigen einen Zusammenhang, aber keine Ursache. Menschen, die mehrere Sprachen sprechen, unterscheiden sich vielleicht auch in anderen Dingen.

Lohnt es sich also, erst später anzufangen? Eine Studie aus Schottland fand: Auch wer erst als Erwachsener eine zweite Sprache gelernt hatte, schnitt im Alter besser ab, als die Testergebnisse aus der Kindheit erwarten ließen. In einem Versuch in Schweden dagegen veränderte sich das Gedächtnis älterer Menschen nach einem elfwöchigen Italienischkurs nicht.

Ehrlich gesagt: Eine sichere Antwort gibt es noch nicht. Aber eine neue Sprache gibt euch einen Grund, mit neuen Menschen zu reden. Und das kann nicht schaden.',
   '["https://doi.org/10.1038/s43587-025-01000-2", "https://doi.org/10.1002/ana.24158"]'::jsonb, 75)
on conflict (id) do nothing;
