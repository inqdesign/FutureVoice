-- French becomes a selectable target language (2026-11-13), so it gets its
-- own Season 1 and the two challenges every target language started with,
-- each WRITTEN in French rather than translated (same rule as
-- `20261010150000` and `20261015160000`). Addressed to the room (vous), the
-- way a talk is given; typographic apostrophes and the no-break space before
-- ? and : as French writes them.
--
--   * ...0000000f0001 is the bundled sample (`SpeechLibrary.builtInId("fr")`),
--     so its text must stay byte-identical to `builtInBodies["fr"]` in the app.
--   * ...0000000f0002 is the ageing study, the same claims as the other
--     languages' copies: "risquaient davantage", not "deux fois plus" (the
--     odds ratio is 2.11, the relative risk 1.43).
--
-- Ids far from the daily challenges' running numbers (…0020 onwards), so the
-- two can't collide.

insert into public.speech_seasons (language, season, min_scoring, opened_at)
values ('fr', 1, 2, now())
on conflict (language, season) do nothing;

insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-0000000f0001', 'fr', 'Pourquoi s’entraîner à voix haute ?', 'explainer',
   'Ça vous est déjà arrivé ? Dans votre tête, la phrase est parfaite. Et au moment de la dire, elle s’écroule.

Parler, c’est un savoir-faire, pas seulement un savoir. Vous pouvez connaître tous les mots et toute la grammaire : si votre bouche n’a jamais construit cette phrase, elle vous lâchera au moment où vous en aurez besoin. C’est pour ça qu’il faut s’entraîner à voix haute.

Dire les choses à voix haute aide aussi à les retenir. Des études suggèrent qu’on se souvient mieux de ce qu’on a dit que de ce qu’on a seulement lu.

Et si vous vous enregistrez, vous remarquerez des choses qui vous échappent autrement : à quelle vitesse vous parlez vraiment, combien de fois vous dites « euh », et si votre voix baisse à la fin des phrases.

Une présentation, un entretien, même une première conversation avec quelqu’un de nouveau : tout devient plus facile avec de l’entraînement. Et la minute que vous venez de passer à lire ce texte à voix haute ? C’était votre premier entraînement.', 60)
on conflict (id) do nothing;

insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds)
values
  ('5beec000-0000-4000-8000-0000000f0002', 'fr', 'Les langues nous gardent-elles jeunes ?', 'explainer',
   'Vous avez sans doute déjà entendu dire qu’apprendre une langue pouvait ralentir le vieillissement. Ça paraît presque trop beau pour être vrai. Alors, regardons ce que dit vraiment la recherche.

En 2025, la revue Nature Aging a publié une très grande étude. Les chercheurs ont analysé plus de quatre-vingt-six mille personnes de cinquante et un à quatre-vingt-dix ans, dans vingt-sept pays européens. Les personnes qui ne parlaient qu’une seule langue risquaient davantage de vieillir plus vite que prévu. Et plus quelqu’un parlait de langues, plus ce risque était faible.

Mais attention à un détail important. Une étude comme celle-ci montre un lien, pas une cause. Les gens qui parlent plusieurs langues peuvent aussi être différents sur d’autres points.

Alors, est-ce que ça vaut la peine de commencer plus tard ? Une étude en Écosse a montré que les personnes qui avaient appris une deuxième langue à l’âge adulte s’en sortaient elles aussi mieux en vieillissant que ne le prédisaient leurs tests d’enfance. En revanche, en Suède, des personnes âgées qui ont suivi un cours d’italien de onze semaines n’ont montré aucun changement de mémoire.

La réponse honnête, c’est qu’on ne le sait pas encore vraiment. Mais une nouvelle langue vous donne une raison de parler à de nouvelles personnes. Et ça, ça ne peut pas faire de mal.',
   '["https://doi.org/10.1038/s43587-025-01000-2", "https://doi.org/10.1002/ana.24158"]'::jsonb, 75)
on conflict (id) do nothing;
